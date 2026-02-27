import * as pulumi from "@pulumi/pulumi";
import {
  githubToken,
  githubUsername,
  claudeCodeOauthToken,
  slackBotToken,
  slackAppToken,
  assistantName,
  webAuthToken,
  stixMcpUrl,
  stixApiKey,
} from "./config";

// Constructs the .env content string from Pulumi config values.
// Used by compute.ts (cloud-init) and github-environments.ts (deploy secret).
export const dotenvContent: pulumi.Output<string> = pulumi
  .all([githubToken, claudeCodeOauthToken, slackBotToken, slackAppToken, webAuthToken, stixApiKey])
  .apply(([ghToken, claudeToken, slackBot, slackApp, webAuth, stixKey]) =>
    [
      `GITHUB_TOKEN=${ghToken}`,
      `GITHUB_USERNAME=${githubUsername}`,
      `CLAUDE_CODE_OAUTH_TOKEN=${claudeToken}`,
      `SLACK_BOT_TOKEN=${slackBot}`,
      `SLACK_APP_TOKEN=${slackApp}`,
      `ASSISTANT_NAME=${assistantName}`,
      `WEB_AUTH_TOKEN=${webAuth}`,
      `STIX_MCP_URL=${stixMcpUrl}`,
      `STIX_API_KEY=${stixKey}`,
    ].join("\n") + "\n"
  );
