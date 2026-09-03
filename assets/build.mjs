import { build } from "esbuild"
import { sentryEsbuildPlugin } from "@sentry/esbuild-plugin"
import path from "node:path"
import { fileURLToPath } from "node:url"

const applicationKey = "kaguya"
const assetsDir = path.dirname(fileURLToPath(import.meta.url))
const projectDir = path.resolve(assetsDir, "..")
const staticJsDir = path.resolve(assetsDir, "../priv/static/assets/js")
const mixBuildPath = process.env.MIX_BUILD_PATH
  ? path.resolve(projectDir, process.env.MIX_BUILD_PATH)
  : path.join(projectDir, "_build", process.env.MIX_ENV || "dev")
const deploy = process.argv.includes("--deploy")
const onlyArg = process.argv.find(arg => arg.startsWith("--only="))
const only = onlyArg?.slice("--only=".length)

const entries = {
  kaguya: { entryPoint: "js/app.js", outfile: "app.js" },
  list_layout_island: {
    entryPoint: "js/list_layout_island.jsx",
    outfile: "list_layout_island.js",
    format: "esm",
  },
  favorites_dnd_island: {
    entryPoint: "js/favorites_dnd_island.jsx",
    outfile: "favorites_dnd_island.js",
    format: "esm",
  },
}

const selectedEntries = only ? [[only, entries[only]]] : Object.entries(entries)

if (selectedEntries.some(([, config]) => !config)) {
  throw new Error(`Unknown asset entry: ${only}`)
}

const sentryPlugin = () =>
  sentryEsbuildPlugin({
    applicationKey,
    telemetry: false,
    silent: true,
    sourcemaps: { disable: true },
    release: { inject: false, create: false, finalize: false },
  })

await Promise.all(
  selectedEntries.map(([, entry]) =>
    build({
      absWorkingDir: assetsDir,
      entryPoints: [entry.entryPoint],
      outfile: path.join(staticJsDir, entry.outfile),
      bundle: true,
      target: "es2022",
      format: entry.format,
      external: ["/fonts/*", "/images/*"],
      nodePaths: [path.join(projectDir, "deps"), mixBuildPath],
      minify: deploy,
      sourcemap: deploy ? "linked" : false,
      define: {
        __KAGUYA_SENTRY_APPLICATION_KEY__: JSON.stringify(applicationKey),
      },
      plugins: [sentryPlugin()],
      logLevel: "info",
    })
  )
)
