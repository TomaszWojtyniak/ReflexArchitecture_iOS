// Behavior-test SDK: drives the headless inventory-cli over newline-delimited JSON.
// No dependencies, Node built-ins only.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';

const CLI = fileURLToPath(new URL('../Core/.build/debug/inventory-cli', import.meta.url));
const POLL_MS = 10;
const TIMEOUT_MS = 2000;
const ANSWER_MS = 60_000; // generous: macOS may scan a freshly built binary on its first launch

export const fixture = (name) => fileURLToPath(new URL(`./fixtures/${name}.json`, import.meta.url));

export function createBehaviorSession({ fixtures = [], cli = CLI, answerTimeoutMs = ANSWER_MS } = {}) {
  const child = spawn(cli, ['--fixtures', ...fixtures]);
  const waiting = []; // pending requests, answered by stdout lines in order
  let stderr = '';
  let exited = null; // the error every call gets once the session is over

  // Ends the session: pending and later calls reject with the first reason.
  function fail(error) {
    exited ??= error;
    for (const request of waiting.splice(0)) {
      clearTimeout(request.timer);
      request.reject(exited);
    }
    child.kill();
  }

  child.stderr.on('data', (chunk) => (stderr += chunk));
  child.stdin.on('error', () => {}); // EPIPE after exit; 'close' reports why
  createInterface({ input: child.stdout }).on('line', (line) => {
    const request = waiting.shift();
    if (!request) return;
    clearTimeout(request.timer);
    try {
      request.resolve(JSON.parse(line));
    } catch {
      request.reject(new Error(`inventory-cli answered with non-JSON: ${line}`));
    }
  });
  child.on('close', (code) => fail(new Error(`inventory-cli exited with code ${code}: ${stderr.trim()}`)));

  function request(body) {
    if (exited) return Promise.reject(exited);
    return new Promise((resolve, reject) => {
      // A CLI that stops answering fails the session instead of hanging the run.
      const timer = setTimeout(
        () => fail(new Error(`inventory-cli did not answer ${JSON.stringify(body)} within ${answerTimeoutMs} ms`)),
        answerTimeoutMs,
      );
      waiting.push({ resolve, reject, timer });
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
    async close() {
      try {
        if (!exited) await ls(); // a violation caused by the last step only shows on the next command
      } finally {
        child.stdin.end();
        child.kill();
      }
    },
  };
}
