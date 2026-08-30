import { optimizeCapability } from "../../../src/capabilities/optimize.ts";
import { createHandler } from "../../../src/pipeline.ts";
import { runtime } from "../../../src/runtime.ts";

const { config, store, adapter, integrity } = runtime();

export default createHandler(optimizeCapability, { config, store, adapter, integrity });
