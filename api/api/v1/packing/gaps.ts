import { gapsCapability } from "../../../src/capabilities/gaps.ts";
import { createHandler } from "../../../src/pipeline.ts";
import { runtime } from "../../../src/runtime.ts";

const { config, store, adapter, integrity } = runtime();

export default createHandler(gapsCapability, { config, store, adapter, integrity });
