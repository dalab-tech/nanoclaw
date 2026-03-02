/**
 * NanoClaw Enterprise Control Plane API
 *
 * Manages tenant lifecycle: provisioning, scaling, monitoring, and deprovisioning.
 * Deployed on Cloud Run. Uses Cloud SQL (PostgreSQL) for tenant metadata
 * and kubectl/Terraform for Kubernetes operations.
 */
import { Hono } from 'hono';
import { bearerAuth } from 'hono/bearer-auth';
import { zValidator } from '@hono/zod-validator';
import { serve } from '@hono/node-server';
import { z } from 'zod';
import { execSync } from 'child_process';

const app = new Hono();
const PORT = parseInt(process.env.PORT || '8080', 10);
const API_TOKEN = process.env.API_TOKEN || '';
const GKE_CLUSTER = process.env.GKE_CLUSTER || 'nanoclaw-prod';
const GKE_REGION = process.env.GKE_REGION || 'us-central1';
const REGISTRY_URL = process.env.REGISTRY_URL || '';
const PROJECT_ID = process.env.GCP_PROJECT_ID || '';

// Health check (no auth)
app.get('/healthz', (c) => c.json({ status: 'ok' }));

// Auth for all API routes
if (API_TOKEN) {
  app.use('/api/*', bearerAuth({ token: API_TOKEN }));
}

// --- Schemas ---

const createTenantSchema = z.object({
  tenantId: z.string().regex(/^[a-z][a-z0-9-]{2,30}$/),
  tenantName: z.string().min(1).max(200),
  assistantName: z.string().min(1).max(64).default('Andy'),
  channels: z.array(z.enum(['whatsapp', 'slack', 'github', 'web'])).default(['web']),
  maxConcurrentContainers: z.number().min(1).max(20).default(5),
  storageSize: z.string().default('10Gi'),
  anthropicApiKey: z.string().min(1),
});

const updateTenantSchema = z.object({
  assistantName: z.string().min(1).max(64).optional(),
  maxConcurrentContainers: z.number().min(1).max(20).optional(),
  imageTag: z.string().optional(),
});

// --- Helper: run kubectl ---

function kubectl(args: string): string {
  return execSync(`kubectl ${args}`, {
    encoding: 'utf-8',
    timeout: 30_000,
  }).trim();
}

// --- Tenant CRUD ---

// List all tenants
app.get('/api/tenants', (c) => {
  const namespaces = kubectl(
    'get namespaces -l nanoclaw.io/managed-by=terraform -o json'
  );
  const parsed = JSON.parse(namespaces);
  const tenants = parsed.items.map((ns: { metadata: { name: string; labels: Record<string, string>; annotations: Record<string, string> } }) => ({
    id: ns.metadata.labels['nanoclaw.io/tenant'],
    name: ns.metadata.annotations?.['nanoclaw.io/tenant-name'] || '',
    namespace: ns.metadata.name,
  }));
  return c.json({ tenants });
});

// Get tenant status
app.get('/api/tenants/:id', (c) => {
  const { id } = c.req.param();
  const ns = `tenant-${id}`;

  try {
    const pods = kubectl(
      `get pods -n ${ns} -l app=nanoclaw -o json`
    );
    const parsed = JSON.parse(pods);
    const pod = parsed.items[0];

    if (!pod) {
      return c.json({ error: { code: 'NOT_FOUND', message: 'Tenant not found' } }, 404);
    }

    const status = {
      tenantId: id,
      namespace: ns,
      pod: {
        name: pod.metadata.name,
        phase: pod.status.phase,
        ready: pod.status.containerStatuses?.every((cs: { ready: boolean }) => cs.ready) ?? false,
        restartCount: pod.status.containerStatuses?.reduce(
          (sum: number, cs: { restartCount: number }) => sum + cs.restartCount, 0
        ) ?? 0,
        startTime: pod.status.startTime,
      },
      containers: pod.status.containerStatuses?.map((cs: { name: string; ready: boolean; restartCount: number; state: object }) => ({
        name: cs.name,
        ready: cs.ready,
        restartCount: cs.restartCount,
        state: cs.state,
      })) ?? [],
    };

    return c.json(status);
  } catch {
    return c.json({ error: { code: 'NOT_FOUND', message: 'Tenant not found' } }, 404);
  }
});

// Provision new tenant
app.post('/api/tenants', zValidator('json', createTenantSchema), async (c) => {
  const input = c.req.valid('json');
  const ns = `tenant-${input.tenantId}`;

  // Check if namespace already exists
  try {
    kubectl(`get namespace ${ns}`);
    return c.json(
      { error: { code: 'ALREADY_EXISTS', message: `Tenant ${input.tenantId} already exists` } },
      409,
    );
  } catch {
    // Expected — namespace doesn't exist yet
  }

  // Store API key in Secret Manager
  try {
    execSync(
      `echo -n "${input.anthropicApiKey}" | gcloud secrets create nanoclaw-${input.tenantId}-anthropic-api-key --data-file=- --project=${PROJECT_ID}`,
      { timeout: 15_000 },
    );
  } catch {
    // Secret may already exist — try to add a new version
    execSync(
      `echo -n "${input.anthropicApiKey}" | gcloud secrets versions add nanoclaw-${input.tenantId}-anthropic-api-key --data-file=- --project=${PROJECT_ID}`,
      { timeout: 15_000 },
    );
  }

  // Create namespace
  kubectl(`create namespace ${ns}`);
  kubectl(`label namespace ${ns} nanoclaw.io/tenant=${input.tenantId} nanoclaw.io/managed-by=terraform`);
  kubectl(`annotate namespace ${ns} nanoclaw.io/tenant-name="${input.tenantName}"`);

  // Create Kubernetes secret from Secret Manager value
  kubectl(
    `create secret generic nanoclaw-secrets -n ${ns} --from-literal=anthropic-api-key="${input.anthropicApiKey}"`
  );

  // Create PVC
  const pvcYaml = JSON.stringify({
    apiVersion: 'v1',
    kind: 'PersistentVolumeClaim',
    metadata: { name: 'nanoclaw-state', namespace: ns },
    spec: {
      accessModes: ['ReadWriteOnce'],
      storageClassName: 'premium-rwo',
      resources: { requests: { storage: input.storageSize } },
    },
  });
  execSync(`echo '${pvcYaml}' | kubectl apply -f -`, { timeout: 10_000 });

  // Create deployment
  const deployYaml = JSON.stringify({
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: { name: 'nanoclaw', namespace: ns, labels: { app: 'nanoclaw', tenant: input.tenantId } },
    spec: {
      replicas: 1,
      strategy: { type: 'Recreate' },
      selector: { matchLabels: { app: 'nanoclaw', tenant: input.tenantId } },
      template: {
        metadata: { labels: { app: 'nanoclaw', tenant: input.tenantId } },
        spec: {
          terminationGracePeriodSeconds: 120,
          nodeSelector: { pool: 'nanoclaw' },
          containers: [
            {
              name: 'nanoclaw',
              image: `${REGISTRY_URL}/nanoclaw:latest`,
              ports: [{ containerPort: 3100, name: 'web' }],
              env: [
                { name: 'INSTANCE_ID', value: input.tenantId },
                { name: 'ASSISTANT_NAME', value: input.assistantName },
                { name: 'MAX_CONCURRENT_CONTAINERS', value: String(input.maxConcurrentContainers) },
                { name: 'CONTAINER_IMAGE', value: `${REGISTRY_URL}/nanoclaw-agent:latest` },
                { name: 'WEB_CHANNEL_PORT', value: '3100' },
                { name: 'DOCKER_HOST', value: 'tcp://localhost:2375' },
                { name: 'ANTHROPIC_API_KEY', valueFrom: { secretKeyRef: { name: 'nanoclaw-secrets', key: 'anthropic-api-key' } } },
              ],
              resources: {
                requests: { cpu: '500m', memory: '1Gi' },
                limits: { cpu: '2', memory: '4Gi' },
              },
              volumeMounts: [
                { name: 'state', mountPath: '/app/store', subPath: 'store' },
                { name: 'state', mountPath: '/app/groups', subPath: 'groups' },
                { name: 'state', mountPath: '/app/data', subPath: 'data' },
              ],
              livenessProbe: {
                httpGet: { path: '/healthz', port: 3100 },
                initialDelaySeconds: 30,
                periodSeconds: 30,
              },
              readinessProbe: {
                httpGet: { path: '/readyz', port: 3100 },
                initialDelaySeconds: 10,
                periodSeconds: 10,
              },
            },
            {
              name: 'dind',
              image: 'docker:27-dind',
              securityContext: { privileged: true },
              env: [{ name: 'DOCKER_TLS_CERTDIR', value: '' }],
              ports: [{ containerPort: 2375 }],
              resources: {
                requests: { cpu: '1', memory: '2Gi' },
                limits: { cpu: '4', memory: '8Gi' },
              },
              volumeMounts: [
                { name: 'docker-data', mountPath: '/var/lib/docker' },
                { name: 'state', mountPath: '/app/store', subPath: 'store' },
                { name: 'state', mountPath: '/app/groups', subPath: 'groups' },
                { name: 'state', mountPath: '/app/data', subPath: 'data' },
              ],
            },
          ],
          volumes: [
            { name: 'state', persistentVolumeClaim: { claimName: 'nanoclaw-state' } },
            { name: 'docker-data', emptyDir: { sizeLimit: '50Gi' } },
          ],
        },
      },
    },
  });
  execSync(`echo '${deployYaml}' | kubectl apply -f -`, { timeout: 15_000 });

  // Create service
  const svcYaml = JSON.stringify({
    apiVersion: 'v1',
    kind: 'Service',
    metadata: { name: 'nanoclaw', namespace: ns },
    spec: {
      selector: { app: 'nanoclaw', tenant: input.tenantId },
      ports: [{ port: 80, targetPort: 3100, name: 'web' }],
      type: 'ClusterIP',
    },
  });
  execSync(`echo '${svcYaml}' | kubectl apply -f -`, { timeout: 10_000 });

  // Create network policy
  const netpolYaml = JSON.stringify({
    apiVersion: 'networking.k8s.io/v1',
    kind: 'NetworkPolicy',
    metadata: { name: 'isolate-tenant', namespace: ns },
    spec: {
      podSelector: {},
      policyTypes: ['Ingress', 'Egress'],
      egress: [{}],
      ingress: [{
        from: [
          { namespaceSelector: { matchLabels: { 'nanoclaw.io/tenant': input.tenantId } } },
          { namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': 'ingress-nginx' } } },
        ],
      }],
    },
  });
  execSync(`echo '${netpolYaml}' | kubectl apply -f -`, { timeout: 10_000 });

  return c.json({
    tenantId: input.tenantId,
    namespace: ns,
    status: 'provisioning',
    message: 'Tenant created. Pod will be ready in ~60 seconds.',
  }, 201);
});

// Update tenant configuration
app.patch('/api/tenants/:id', zValidator('json', updateTenantSchema), (c) => {
  const { id } = c.req.param();
  const input = c.req.valid('json');
  const ns = `tenant-${id}`;

  const updates: string[] = [];

  if (input.assistantName) {
    kubectl(`set env deployment/nanoclaw ASSISTANT_NAME="${input.assistantName}" -n ${ns}`);
    updates.push(`assistantName=${input.assistantName}`);
  }

  if (input.maxConcurrentContainers) {
    kubectl(`set env deployment/nanoclaw MAX_CONCURRENT_CONTAINERS="${input.maxConcurrentContainers}" -n ${ns}`);
    updates.push(`maxConcurrentContainers=${input.maxConcurrentContainers}`);
  }

  if (input.imageTag) {
    kubectl(`set image deployment/nanoclaw nanoclaw=${REGISTRY_URL}/nanoclaw:${input.imageTag} -n ${ns}`);
    kubectl(`set env deployment/nanoclaw CONTAINER_IMAGE=${REGISTRY_URL}/nanoclaw-agent:${input.imageTag} -n ${ns}`);
    updates.push(`imageTag=${input.imageTag}`);
  }

  return c.json({ tenantId: id, updates });
});

// Delete tenant
app.delete('/api/tenants/:id', (c) => {
  const { id } = c.req.param();
  const ns = `tenant-${id}`;

  try {
    kubectl(`get namespace ${ns}`);
  } catch {
    return c.json({ error: { code: 'NOT_FOUND', message: 'Tenant not found' } }, 404);
  }

  // Delete all resources in the namespace, then the namespace itself
  kubectl(`delete namespace ${ns} --wait=false`);

  return c.json({
    tenantId: id,
    status: 'deprovisioning',
    message: 'Tenant deletion initiated. Resources will be cleaned up.',
  });
});

// --- Tenant Health Overview ---

app.get('/api/health/overview', (c) => {
  const namespaces = kubectl(
    'get namespaces -l nanoclaw.io/managed-by=terraform -o jsonpath="{.items[*].metadata.name}"'
  );

  const tenantNs = namespaces.replace(/"/g, '').split(' ').filter(Boolean);
  const overview = tenantNs.map((ns) => {
    const tenantId = ns.replace('tenant-', '');
    try {
      const podJson = kubectl(`get pods -n ${ns} -l app=nanoclaw -o json`);
      const pods = JSON.parse(podJson);
      const pod = pods.items[0];
      return {
        tenantId,
        namespace: ns,
        healthy: pod?.status?.containerStatuses?.every((cs: { ready: boolean }) => cs.ready) ?? false,
        phase: pod?.status?.phase || 'Unknown',
        restarts: pod?.status?.containerStatuses?.reduce(
          (sum: number, cs: { restartCount: number }) => sum + cs.restartCount, 0
        ) ?? 0,
      };
    } catch {
      return { tenantId, namespace: ns, healthy: false, phase: 'Error', restarts: 0 };
    }
  });

  const healthy = overview.filter((t) => t.healthy).length;
  return c.json({
    totalTenants: overview.length,
    healthy,
    unhealthy: overview.length - healthy,
    tenants: overview,
  });
});

// --- Start server ---

serve({ fetch: app.fetch, port: PORT, hostname: '0.0.0.0' });
console.log(`Control Plane API listening on port ${PORT}`);
