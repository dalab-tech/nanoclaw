import * as pulumi from '@pulumi/pulumi';

const config = new pulumi.Config('cloudflare-dns');

/** Cloudflare account ID (required when email routing destination addresses are managed) */
export const accountId = config.get('accountId');

// =============================================================================
// Zone IDs — all zones managed in a single stack
// =============================================================================
// Set each zone ID via: pulumi config set cloudflare-dns:<key> <zone-id>

export const zones = {
  dalabLol: config.get('dalabLolZoneId'),
  dalabTech: config.get('dalabTechZoneId'),
  iamsonDev: config.get('iamsonDevZoneId'),
  lamsonDev: config.get('lamsonDevZoneId'),
  onedictionaryApp: config.get('onedictionaryAppZoneId'),
  tinaiDev: config.get('tinaiDevZoneId'),
  vibeboardDev: config.get('vibeboardDevZoneId'),
} as const;
