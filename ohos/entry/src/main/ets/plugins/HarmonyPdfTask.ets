import { writeHarmonyPdf } from './HarmonyPdfImport';

// A Concurrent entry may use imported symbols, not same-module closures.
@Concurrent
export async function extractHarmonyPdf(name: string, source: string, output: string): Promise<void> {
  await writeHarmonyPdf(name, source, output);
}
