import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawnSync } from "node:child_process";
import { join } from "node:path";

const GUARDS = join(process.env.FACTORY_HOME ?? "", "guards");

function check(script: string, arg: string) {
  const r = spawnSync(join(GUARDS, script), [arg], { encoding: "utf8" });
  if (r.status === 0) return undefined;
  return { block: true, reason: r.stderr.trim() || `Blocked by factory guard ${script}` };
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event) => {
    if (event.toolName === "bash") return check("bash.sh", event.input?.command ?? "");
    if (event.toolName === "edit" || event.toolName === "write")
      return check("files.sh", event.input?.path ?? ""); // Pi's edit and write tools take `path`
  });
}
