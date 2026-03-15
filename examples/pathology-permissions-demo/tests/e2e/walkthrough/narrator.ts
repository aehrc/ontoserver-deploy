import * as readline from 'node:readline';

const GREEN = '\x1b[0;32m';
const YELLOW = '\x1b[1;33m';
const BLUE = '\x1b[0;34m';
const CYAN = '\x1b[0;36m';
const NC = '\x1b[0m';

let stepNumber = 0;
let auto = false;

/**
 * Enable auto mode — skips pauses and auto-skips on errors.
 * Useful for CI or non-interactive testing.
 */
export function setAutoMode(enabled: boolean): void {
  auto = enabled;
}

/**
 * Print a numbered step header with a cyan border box.
 */
export function step(title: string): void {
  stepNumber++;
  console.log('');
  console.log(`${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}`);
  console.log(`${CYAN}  Step ${stepNumber}: ${title}${NC}`);
  console.log(`${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}`);
  console.log('');
}

/**
 * Print blue explanation text.
 */
export function explain(text: string): void {
  console.log(`${BLUE}${text}${NC}`);
}

/**
 * Print green highlighted observation text.
 */
export function highlight(text: string): void {
  console.log(`${GREEN}${text}${NC}`);
}

/**
 * Print a yellow warning.
 */
export function warn(text: string): void {
  console.log(`${YELLOW}${text}${NC}`);
}

/**
 * Pause execution and wait for the presenter to press Enter.
 */
export async function pause(message?: string): Promise<void> {
  if (auto) {
    console.log(`\n${YELLOW}${message || '[auto] continuing...'}${NC}`);
    return;
  }

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise<void>((resolve) => {
    rl.question(
      `\n${YELLOW}${message || 'Press Enter to continue...'}${NC}`,
      () => {
        rl.close();
        resolve();
      },
    );
  });
}

/**
 * Prompt for retry/skip/quit when a scene fails.
 * Returns 'retry', 'skip', or 'quit'.
 */
export async function promptOnError(error: Error): Promise<'retry' | 'skip' | 'quit'> {
  warn(`Error: ${error.message}`);

  if (auto) {
    warn('[auto] skipping scene');
    return 'skip';
  }

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise<'retry' | 'skip' | 'quit'>((resolve) => {
    rl.question(
      `${YELLOW}[r]etry / [s]kip / [q]uit: ${NC}`,
      (answer) => {
        rl.close();
        const choice = answer.trim().toLowerCase();
        if (choice === 'r' || choice === 'retry') resolve('retry');
        else if (choice === 'q' || choice === 'quit') resolve('quit');
        else resolve('skip');
      },
    );
  });
}

/**
 * Reset step counter (useful if restarting).
 */
export function resetSteps(): void {
  stepNumber = 0;
}
