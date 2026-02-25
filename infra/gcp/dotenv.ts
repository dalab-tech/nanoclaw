import * as pulumi from "@pulumi/pulumi";
import {
  envGithubToken,
  githubUsername,
  claudeCodeOauthToken,
  slackBotToken,
  slackAppToken,
  assistantName,
} from "./config";

// Constructs the .env content string from Pulumi config values.
// Used by compute.ts (cloud-init) and github-environments.ts (deploy secret).
export const dotenvContent: pulumi.Output<string> = pulumi
  .all([envGithubToken, claudeCodeOauthToken, slackBotToken, slackAppToken])
  .apply(([ghToken, claudeToken, slackBot, slackApp]) =>
    [
      `GITHUB_TOKEN=${ghToken}`,
      `GITHUB_USERNAME=${githubUsername}`,
      `CLAUDE_CODE_OAUTH_TOKEN=${claudeToken}`,
      `SLACK_BOT_TOKEN=${slackBot}`,
      `SLACK_APP_TOKEN=${slackApp}`,
      `ASSISTANT_NAME=${assistantName}`,
    ].join("\n") + "\n"
  );
