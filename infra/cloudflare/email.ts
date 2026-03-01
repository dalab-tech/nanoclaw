import * as pulumi from '@pulumi/pulumi';
import * as cloudflare from '@pulumi/cloudflare';
import { accountId, zones } from './zones';

// =============================================================================
// Shared types/helpers
// =============================================================================

type EmailForward = { name: string; destination: string };

type EmailDestinationRegistryConfig = {
  accountId: string;
  destinationEmails: string[];
  existingDestinationAddressIdsByEmail: Record<string, string>;
};

type DomainEmailConfig = {
  domain: string;
  resourcePrefix: string;
  forwardResourcePrefix?: string;
  zoneId: string;
  forwards: EmailForward[];
  destinationAddressesByEmail: Record<string, cloudflare.EmailRoutingAddress>;
};

const slugifyEmailForResource = (email: string): string =>
  email
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');

class EmailDestinationRegistry extends pulumi.ComponentResource {
  public readonly addresses: Record<string, cloudflare.EmailRoutingAddress>;

  constructor(
    name: string,
    { accountId, destinationEmails, existingDestinationAddressIdsByEmail }: EmailDestinationRegistryConfig
  ) {
    super('dalab:cloudflare:EmailDestinationRegistry', name);

    this.addresses = {};
    const childOpts: pulumi.CustomResourceOptions = { parent: this };

    for (const destinationEmail of destinationEmails) {
      const destinationAddressIdentifier = existingDestinationAddressIdsByEmail[destinationEmail];
      const importId = destinationAddressIdentifier
        ? destinationAddressIdentifier.includes('/')
          ? destinationAddressIdentifier
          : `${accountId}/${destinationAddressIdentifier}`
        : undefined;
      const resourceOpts = importId ? { ...childOpts, import: importId } : childOpts;

      this.addresses[destinationEmail] = new cloudflare.EmailRoutingAddress(
        `email-destination-${slugifyEmailForResource(destinationEmail)}`,
        {
          accountId,
          email: destinationEmail,
        },
        resourceOpts
      );
    }

    this.registerOutputs({
      destinationAddressIds: Object.fromEntries(
        Object.entries(this.addresses).map(([email, address]) => [email, address.id])
      ),
      destinationAddressVerifiedAt: Object.fromEntries(
        Object.entries(this.addresses).map(([email, address]) => [email, address.verified])
      ),
    });
  }
}

class DomainEmailGroup extends pulumi.ComponentResource {
  public readonly emailRouting: cloudflare.EmailRoutingSettings;
  public readonly forwardingRules: cloudflare.EmailRoutingRule[];

  constructor(
    name: string,
    { domain, resourcePrefix, forwardResourcePrefix, zoneId, forwards, destinationAddressesByEmail }: DomainEmailConfig
  ) {
    super('dalab:cloudflare:DomainEmailGroup', name);

    const childOpts: pulumi.CustomResourceOptions = {
      parent: this,
      // Old resources were created directly under the stack (no parent).
      aliases: [{ parent: pulumi.rootStackResource }],
    };

    this.emailRouting = new cloudflare.EmailRoutingSettings(`${resourcePrefix}-email-routing`, { zoneId }, childOpts);

    this.forwardingRules = forwards.map(({ name: localPart, destination }) => {
      const destinationAddress = destinationAddressesByEmail[destination];
      if (!destinationAddress) {
        throw new Error(`Missing EmailRoutingAddress resource for destination: ${destination}`);
      }

      return new cloudflare.EmailRoutingRule(
        `${forwardResourcePrefix ?? `${resourcePrefix}-email-fwd`}-${localPart}`,
        {
          zoneId,
          name: `Forward ${localPart}@${domain}`,
          enabled: true,
          matchers: [
            {
              type: 'literal',
              field: 'to',
              value: `${localPart}@${domain}`,
            },
          ],
          actions: [
            {
              type: 'forward',
              values: [destinationAddress.email],
            },
          ],
        },
        {
          ...childOpts,
          dependsOn: [destinationAddress],
        }
      );
    });

    this.registerOutputs({
      emailRoutingId: this.emailRouting.id,
      forwardingRuleIds: this.forwardingRules.map((rule) => rule.id),
    });
  }
}

// =============================================================================
// Per-domain forwarding map
// =============================================================================
// This resource enables email routing on each configured zone.
// Cloudflare auto-creates MX and SPF records — do NOT add them manually in dns.ts.
//
// Required API token permissions:
//   Account -> Email Routing Addresses -> Edit
//   Zone -> Email Routing Rules -> Edit
//
// The destination inboxes must still be verified in Cloudflare (verification email).

const dalabTechForwards: EmailForward[] = [
  // Inbox
  { name: 'hi', destination: 'dalab.inbox+hi@gmail.com' },
  { name: 'hello', destination: 'dalab.inbox+hello@gmail.com' },
  { name: 'us', destination: 'dalab.inbox+us@gmail.com' },
  { name: 'support', destination: 'dalab.inbox+support@gmail.com' },
  // Inbox/Billing - Need to update
  { name: 'inbox', destination: 'dev.lamson+dalab.inbox@gmail.com' },
  { name: 'billing', destination: 'dev.lamson+dalab.billing@gmail.com' },
  // Bot
  { name: 'anton', destination: 'dev.lamson+dalab.anton@gmail.com' },
  // Personal
  { name: 'son', destination: 'dev.lamson+dalab.son@gmail.com' },
  { name: 'dang', destination: 'dangns229+dalab.dang@gmail.com' },
  { name: 'thoai', destination: 'thoai.vhp+dalab.thoai@gmail.com' },
];

const tinaiDevForwards: EmailForward[] = [
  { name: 'hi', destination: 'dev.lamson+tinai.inbox@gmail.com' },
  { name: 'hello', destination: 'dev.lamson+tinai.inbox@gmail.com' },
  { name: 'inbox', destination: 'dev.lamson+tinai.inbox@gmail.com' },
  // Feed
  { name: 'feed', destination: 'tinai.inbox+feed@gmail.com' },
];

const iamsonDevForwards: EmailForward[] = [
  { name: 'hi', destination: 'dev.lamson+iamson.hi@gmail.com' },
  { name: 'me', destination: 'dev.lamson+iamson.me@gmail.com' },
];

const lamsonDevForwards: EmailForward[] = [
  { name: 'hi', destination: 'dev.lamson+lamson.hi@gmail.com' },
  { name: 'me', destination: 'dev.lamson+lamson.me@gmail.com' },
];

const allForwards: EmailForward[] = [
  ...dalabTechForwards,
  ...tinaiDevForwards,
  ...iamsonDevForwards,
  ...lamsonDevForwards,
];

export const emailForwardingMap: Record<string, Record<string, string>> = {
  'dalab.tech': Object.fromEntries(dalabTechForwards.map((f) => [`${f.name}@dalab.tech`, f.destination])),
  'tinai.dev': Object.fromEntries(tinaiDevForwards.map((f) => [`${f.name}@tinai.dev`, f.destination])),
  'iamson.dev': Object.fromEntries(iamsonDevForwards.map((f) => [`${f.name}@iamson.dev`, f.destination])),
  'lamson.dev': Object.fromEntries(lamsonDevForwards.map((f) => [`${f.name}@lamson.dev`, f.destination])),
};

const destinationEmails = Array.from(new Set(allForwards.map(({ destination }) => destination))).sort();
const emailConfig = new pulumi.Config('cloudflare-dns');
const existingDestinationAddressIdsByEmail =
  emailConfig.getObject<Record<string, string>>('existingDestinationAddressIds') ?? {};

const isAnyEmailRoutingDomainConfigured = Boolean(
  zones.dalabTech || zones.tinaiDev || zones.iamsonDev || zones.lamsonDev
);

if (isAnyEmailRoutingDomainConfigured && !accountId) {
  throw new Error(
    'Missing required config: cloudflare-dns:accountId. This stack manages account-level Email Routing destination addresses.'
  );
}

// =============================================================================
// Account-level destination addresses
// =============================================================================
// Optional migration helper:
//   cloudflare-dns:existingDestinationAddressIds (map)
// Example:
//   {"dev.lamson+dalab.hi@gmail.com":"ea95132c15732412d22c1476fa83f27a"}
// Value can be either destination identifier or full import ID:
//   <account_id>/<destination_identifier>

export const emailDestinations =
  isAnyEmailRoutingDomainConfigured && accountId
    ? new EmailDestinationRegistry('email-destination-addresses', {
        accountId,
        destinationEmails,
        existingDestinationAddressIdsByEmail,
      })
    : undefined;

const destinationAddressesByEmail = emailDestinations?.addresses ?? {};

export const emailDestinationAddressIds = emailDestinations
  ? Object.fromEntries(Object.entries(emailDestinations.addresses).map(([email, address]) => [email, address.id]))
  : {};

export const emailDestinationVerifiedAt = emailDestinations
  ? Object.fromEntries(Object.entries(emailDestinations.addresses).map(([email, address]) => [email, address.verified]))
  : {};

// =============================================================================
// dalab.tech
// =============================================================================

export const dalabTechEmail =
  zones.dalabTech && emailDestinations
    ? new DomainEmailGroup('dalab-tech-email-group', {
        domain: 'dalab.tech',
        resourcePrefix: 'dalab-tech',
        forwardResourcePrefix: 'email-fwd',
        zoneId: zones.dalabTech,
        forwards: dalabTechForwards,
        destinationAddressesByEmail,
      })
    : undefined;

// =============================================================================
// tinai.dev
// =============================================================================

export const tinaiDevEmail =
  zones.tinaiDev && emailDestinations
    ? new DomainEmailGroup('tinai-dev-email-group', {
        domain: 'tinai.dev',
        resourcePrefix: 'tinai-dev',
        zoneId: zones.tinaiDev,
        forwards: tinaiDevForwards,
        destinationAddressesByEmail,
      })
    : undefined;

// =============================================================================
// iamson.dev
// =============================================================================

export const iamsonDevEmail =
  zones.iamsonDev && emailDestinations
    ? new DomainEmailGroup('iamson-dev-email-group', {
        domain: 'iamson.dev',
        resourcePrefix: 'iamson-dev',
        zoneId: zones.iamsonDev,
        forwards: iamsonDevForwards,
        destinationAddressesByEmail,
      })
    : undefined;

// =============================================================================
// lamson.dev
// =============================================================================

export const lamsonDevEmail =
  zones.lamsonDev && emailDestinations
    ? new DomainEmailGroup('lamson-dev-email-group', {
        domain: 'lamson.dev',
        resourcePrefix: 'lamson-dev',
        zoneId: zones.lamsonDev,
        forwards: lamsonDevForwards,
        destinationAddressesByEmail,
      })
    : undefined;

// =============================================================================
// Catch-all rule (optional)
// =============================================================================
// Uncomment to forward all unmatched dalab.tech addresses to one inbox.
//
// export const catchAll = zones.dalabTech
//   ? new cloudflare.EmailRoutingCatchAll('dalab-tech-catch-all', {
//       zoneId: zones.dalabTech,
//       name: 'Catch-all forward',
//       enabled: true,
//       matchers: [{ type: 'all' }],
//       actions: [{ type: 'forward', values: ['catchall@example.com'] }],
//     })
//   : undefined;
