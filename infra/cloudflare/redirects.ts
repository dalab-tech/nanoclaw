import * as cloudflare from '@pulumi/cloudflare';
import { zones } from './zones';

// =============================================================================
// dalab.lol → dalab.tech redirect (301, preserves path + query string)
// =============================================================================
// Only created when dalabLol zone is configured.
// Root and www A records must be proxied: true for Cloudflare to intercept.

export const lolRedirect = zones.dalabLol
  ? new cloudflare.Ruleset('dalab-lol-redirect', {
      zoneId: zones.dalabLol,
      name: 'Redirect dalab.lol to dalab.tech',
      kind: 'zone',
      phase: 'http_request_dynamic_redirect',
      rules: [
        {
          action: 'redirect',
          expression: '(http.host eq "dalab.lol") or (http.host eq "www.dalab.lol")',
          description: '301 redirect dalab.lol → dalab.tech (preserve path)',
          actionParameters: {
            fromValue: {
              statusCode: 301,
              targetUrl: {
                expression: 'concat("https://dalab.tech", http.request.uri.path)',
              },
              preserveQueryString: true,
            },
          },
        },
      ],
    })
  : undefined;
