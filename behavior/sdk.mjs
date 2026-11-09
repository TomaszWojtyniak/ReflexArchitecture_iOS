// Behavior-test SDK: drives the headless inventory-cli over newline-delimited JSON.
// No dependencies, Node built-ins only.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';

const CLI = fileURLToPath(new URL('../Core/.build/debug/inventory-cli', import.meta.url));
const POLL_MS = 10;
const TIMEOUT_MS = 2000;

export const fixture = (name) => fileURLToPath(new URL(`./fixtures/${name}.json`, import.meta.url));

export function createBehaviorSession({ fixtures = [] } = {}) {
  const child = spawn(CLI, ['--fixtures', ...fixtures]);
  const waiting = []; // pending requests, answered by stdout lines in order
  let stderr = '';
  let exited = null; // the error every call gets once the process is gone

  child.stderr.on('data', (chunk) => (stderr += chunk));
  child.stdin.on('error', () => {}); // EPIPE after exit; 'close' reports why
  createInterface({ input: child.stdout }).on('line', (line) => {
    const request = waiting.shift();
    try {
      request?.resolve(JSON.parse(line));
    } catch {
      request?.reject(new Error(`inventory-cli answered with non-JSON: ${line}`));
    }
  });
  child.on('close', (code) => {
    exited = new Error(`inventory-cli exited with code ${code}: ${stderr.trim()}`);
    for (const request of waiting.splice(0)) request.reject(exited);
  });

  function request(body) {
    if (exited) return Promise.reject(exited);
    return new Promise((resolve, reject) => {
      waiting.push({ resolve, reject });
      child.stdin.write(JSON.stringify(body) + '\n');
    });
  }

  const ls = () => request({ cmd: 'ls' });

  // Polls ls until check(node) stops throwing. A dead process fails at once (ls rejects);
  // only failures thrown by the check are retried.
  async function until(check) {
    const deadline = Date.now() + TIMEOUT_MS;
    for (;;) {
      const node = await ls();
      try {
        check(node);
        return node;
      } catch (error) {
        if (Date.now() >= deadline) {
          error.message += `\nlast seen: ${JSON.stringify(node)}`;
          throw error;
        }
      }
      await new Promise((resolve) => setTimeout(resolve, POLL_MS));
    }
  }

  return {
    ls,
    precondition: (name, expectation) =>
      until((node) => {
        assert.equal(node.name, name);
        expectation?.(node);
      }),
    async do({ action, payload, expectation }) {
      const answer = await request({ cmd: 'do', action, payload });
      if (answer.error) throw new Error(`do ${action} refused: ${answer.error}`);
      if (expectation) await until(expectation);
    },
    close() {
      child.stdin.end();
      child.kill();
    },
  };
}
