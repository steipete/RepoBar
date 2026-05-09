#!/usr/bin/env tsx
/**
 * ghrest - GitHub REST CLI helpers for RepoBar
 *
 * Examples:
 *   pnpm ghrest repo steipete/RepoBar
 *   pnpm ghrest traffic steipete/RepoBar --json
 *   pnpm ghrest ci steipete/RepoBar --branch main
 */

import process from 'node:process';
import { Command, Option } from 'commander';
import chalk from 'chalk';
import ora from 'ora';
import { requireToken, resolveEndpointConfig } from './github-env';

type Json = Record<string, unknown> | Array<unknown>;

async function getJson(path: string, opts: { host: string; token: string; allowed?: number[] }) {
  const url = new URL(path, opts.host).toString();
  const resp = await fetch(url, {
    headers: {
      Accept: 'application/vnd.github+json',
      Authorization: `Bearer ${opts.token}`,
      'User-Agent': 'RepoBar-CLI',
    },
  });
  const allowed = new Set([200, 202, ...(opts.allowed ?? [])]);
  if (!allowed.has(resp.status)) {
    const body = await resp.text();
    throw new Error(`HTTP ${resp.status}: ${body}`);
  }
  const rateReset = resp.headers.get('x-ratelimit-reset');
  return {
    json: (await resp.json()) as Json,
    rateReset: rateReset ? Number.parseInt(rateReset, 10) : undefined,
    status: resp.status,
  };
}

function formatRate(reset?: number): string | undefined {
  if (!reset) return;
  return `rate limit resets ${new Date(reset * 1000).toLocaleTimeString()}`;
}

const program = new Command()
  .name('ghrest')
  .description('GitHub REST CLI helpers for RepoBar')
  .addOption(new Option('--token <token>', 'GitHub token (defaults to GITHUB_TOKEN)'))
  .addOption(new Option('--host <url>', 'REST API base (default https://api.github.com)'))
  .option('--json', 'Print raw JSON', false)
  .showHelpAfterError();

program
  .command('repo')
  .argument('<owner/repo>')
  .description('Fetch repository JSON')
  .action(async (slug: string, _opts, cmd: Command) => {
    const spinner = ora('Fetching repo').start();
    try {
      const [owner, name] = slug.split('/');
      if (!owner || !name) throw new Error('Use owner/repo format.');
      const { restEndpoint, token } = resolveEndpointConfig({
        token: cmd.getOptionValue('token'),
        restHost: cmd.getOptionValue('host'),
      });
      const authedToken = requireToken(token);
      const { json, rateReset } = await getJson(`/repos/${owner}/${name}`, {
        host: restEndpoint,
        token: authedToken,
      });
      spinner.stop();
      if (program.getOptionValue('json')) {
        console.log(JSON.stringify(json, null, 2));
      } else {
        const repo = json as Record<string, unknown>;
        console.log(
          [
            chalk.bold(`${owner}/${name}`),
            `Stars: ${repo.stargazers_count ?? 'n/a'}`,
            `Issues: ${repo.open_issues_count ?? 'n/a'}`,
            `Default branch: ${repo.default_branch ?? 'n/a'}`,
          ].join('\n')
        );
      }
      if (!program.getOptionValue('json')) {
        const rl = formatRate(rateReset);
        if (rl) console.log(chalk.dim(rl));
      }
    } catch (error) {
      spinner.stop();
      console.error(chalk.red((error as Error).message));
      process.exitCode = 1;
    }
  });

program
  .command('ci')
  .argument('<owner/repo>')
  .option('--branch <name>', 'Branch to filter', 'main')
  .description('Show latest Actions run for a branch')
  .action(async (slug: string, opts: { branch: string }, cmd: Command) => {
    const spinner = ora('Fetching CI status').start();
    try {
      const [owner, name] = slug.split('/');
      if (!owner || !name) throw new Error('Use owner/repo format.');
      const { restEndpoint, token } = resolveEndpointConfig({
        token: cmd.getOptionValue('token'),
        restHost: cmd.getOptionValue('host'),
      });
      const authedToken = requireToken(token);
      const { json, rateReset } = await getJson(
        `/repos/${owner}/${name}/actions/runs?per_page=1&branch=${encodeURIComponent(opts.branch)}`,
        { host: restEndpoint, token: authedToken }
      );
      spinner.stop();
      const runs = (json as { workflow_runs?: Array<Record<string, unknown>> }).workflow_runs ?? [];
      const run = runs[0];
      if (program.getOptionValue('json')) {
        console.log(JSON.stringify(json, null, 2));
      } else if (run) {
        console.log(
          [
            chalk.bold(`${owner}/${name}@${opts.branch}`),
            `Status: ${run.status ?? 'unknown'}`,
            `Conclusion: ${run.conclusion ?? 'n/a'}`,
          ].join('\n')
        );
      } else {
        console.log('No runs found.');
      }
      if (!program.getOptionValue('json')) {
        const rl = formatRate(rateReset);
        if (rl) console.log(chalk.dim(rl));
      }
    } catch (error) {
      spinner.stop();
      console.error(chalk.red((error as Error).message));
      process.exitCode = 1;
    }
  });

program
  .command('traffic')
  .argument('<owner/repo>')
  .description('Fetch traffic views and clones (requires repo admin permission)')
  .action(async (slug: string, _opts, cmd: Command) => {
    const spinner = ora('Fetching traffic').start();
    try {
      const [owner, name] = slug.split('/');
      const { restEndpoint, token } = resolveEndpointConfig({
        token: cmd.getOptionValue('token'),
        restHost: cmd.getOptionValue('host'),
      });
      const authedToken = requireToken(token);
      const [viewsResp, clonesResp] = await Promise.all([
        getJson(`/repos/${owner}/${name}/traffic/views`, { host: restEndpoint, token: authedToken }),
        getJson(`/repos/${owner}/${name}/traffic/clones`, { host: restEndpoint, token: authedToken }),
      ]);
      spinner.stop();
      if (program.getOptionValue('json')) {
        console.log(JSON.stringify({ views: viewsResp.json, clones: clonesResp.json }, null, 2));
      } else {
        console.log(chalk.bold(`${owner}/${name} traffic (last 14d)`));
        console.log(`Unique visitors: ${(viewsResp.json as { uniques?: number }).uniques ?? 'n/a'}`);
        console.log(`Unique cloners: ${(clonesResp.json as { uniques?: number }).uniques ?? 'n/a'}`);
      }
      if (!program.getOptionValue('json')) {
        const rl = formatRate(viewsResp.rateReset ?? clonesResp.rateReset);
        if (rl) console.log(chalk.dim(rl));
      }
    } catch (error) {
      spinner.stop();
      console.error(chalk.red((error as Error).message));
      process.exitCode = 1;
    }
  });

program
  .command('heatmap')
  .argument('<owner/repo>')
  .description('Fetch commit_activity for heatmap (weekly buckets)')
  .action(async (slug: string, _opts, cmd: Command) => {
    const spinner = ora('Fetching commit activity').start();
    try {
      const [owner, name] = slug.split('/');
      const { restEndpoint, token } = resolveEndpointConfig({
        token: cmd.getOptionValue('token'),
        restHost: cmd.getOptionValue('host'),
      });
      const authedToken = requireToken(token);
      const { json, rateReset, status } = await getJson(
        `/repos/${owner}/${name}/stats/commit_activity`,
        { host: restEndpoint, token: authedToken, allowed: [202] }
      );
      spinner.stop();
      if (status === 202) {
        console.log(chalk.yellow('GitHub is computing stats; retry in ~1 minute.'));
        return;
      }
      if (program.getOptionValue('json')) {
        console.log(JSON.stringify(json, null, 2));
      } else {
        const weeks = json as Array<{ total?: number }>;
        const total = weeks.reduce((sum, w) => sum + (w.total ?? 0), 0);
        console.log(chalk.bold(`${owner}/${name}`));
        console.log(`Weeks: ${weeks.length}, total commits: ${total}`);
      }
      if (!program.getOptionValue('json')) {
        const rl = formatRate(rateReset);
        if (rl) console.log(chalk.dim(rl));
      }
    } catch (error) {
      spinner.stop();
      console.error(chalk.red((error as Error).message));
      process.exitCode = 1;
    }
  });

program
  .command('activity')
  .argument('<owner/repo>')
  .description('Latest issue or PR comment')
  .action(async (slug: string, _opts, cmd: Command) => {
    const spinner = ora('Fetching latest activity').start();
    try {
      const [owner, name] = slug.split('/');
      const { restEndpoint, token } = resolveEndpointConfig({
        token: cmd.getOptionValue('token'),
        restHost: cmd.getOptionValue('host'),
      });
      const authedToken = requireToken(token);
      const [issues, reviews] = await Promise.all([
        getJson(
          `/repos/${owner}/${name}/issues/comments?per_page=1&sort=created&direction=desc`,
          { host: restEndpoint, token: authedToken }
        ),
        getJson(
          `/repos/${owner}/${name}/pulls/comments?per_page=1&sort=created&direction=desc`,
          { host: restEndpoint, token: authedToken }
        ),
      ]);
      spinner.stop();
      const candidates = [
        ...(issues.json as Array<Record<string, unknown>>),
        ...(reviews.json as Array<Record<string, unknown>>),
      ];
      const latest = candidates.sort(
        (a, b) => new Date(String(b.created_at)).getTime() - new Date(String(a.created_at)).getTime()
      )[0];
      if (program.getOptionValue('json')) {
        console.log(JSON.stringify(latest ?? {}, null, 2));
      } else if (latest) {
        console.log(chalk.bold(`${owner}/${name}`));
        console.log(`${latest.user?.login}: ${(latest.body ?? '').toString().slice(0, 80)}…`);
        console.log(chalk.dim(latest.html_url ?? ''));
      } else {
        console.log('No comments found.');
      }
      if (!program.getOptionValue('json')) {
        const rl = formatRate(issues.rateReset ?? reviews.rateReset);
        if (rl) console.log(chalk.dim(rl));
      }
    } catch (error) {
      spinner.stop();
      console.error(chalk.red((error as Error).message));
      process.exitCode = 1;
    }
  });

program
  .command('release')
  .argument('<owner/repo>')
  .description('Latest non-draft release (includes prereleases)')
  .action(async (slug: string, _opts, cmd: Command) => {
    const spinner = ora('Fetching releases').start();
    try {
      const [owner, name] = slug.split('/');
      const { restEndpoint, token } = resolveEndpointConfig({
        token: cmd.getOptionValue('token'),
        restHost: cmd.getOptionValue('host'),
      });
      const authedToken = requireToken(token);
      const { json, rateReset } = await getJson(
        `/repos/${owner}/${name}/releases?per_page=10`,
        { host: restEndpoint, token: authedToken, allowed: [404] }
      );
      spinner.stop();
      if (program.getOptionValue('json')) {
        console.log(JSON.stringify(json, null, 2));
      } else {
        const releases = json as Array<Record<string, unknown>>;
        const filtered = releases.filter((r) => r.draft !== true);
        const rel = filtered[0];
        if (rel) {
          const date = rel.published_at ?? rel.created_at;
          console.log(chalk.bold(`${owner}/${name}`));
          console.log(`${rel.name ?? rel.tag_name} (${date ?? 'n/a'})`);
          console.log(chalk.dim(rel.html_url ?? ''));
        } else {
          console.log('No releases found.');
        }
      }
      if (!program.getOptionValue('json')) {
        const rl = formatRate(rateReset);
        if (rl) console.log(chalk.dim(rl));
      }
    } catch (error) {
      spinner.stop();
      console.error(chalk.red((error as Error).message));
      process.exitCode = 1;
    }
  });

program.parseAsync(process.argv);
