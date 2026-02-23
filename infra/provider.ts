import * as pulumi from "@pulumi/pulumi";
import * as oci from "@pulumi/oci";

// Explicit provider — uses ONLY Pulumi stack config, ignores ~/.oci/config
const config = new pulumi.Config("oci");

export const provider = new oci.Provider("oci", {
  tenancyOcid: config.require("tenancyOcid"),
  userOcid: config.require("userOcid"),
  fingerprint: config.require("fingerprint"),
  region: config.require("region"),
  privateKey: config.requireSecret("privateKey"),
});
