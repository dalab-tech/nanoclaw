import * as github from "@pulumi/github";
import { githubToken, githubOwner } from "./config";

// GitHub provider — authenticated with a PAT
export const githubProvider = new github.Provider("github", {
  owner: githubOwner,
  token: githubToken,
});
