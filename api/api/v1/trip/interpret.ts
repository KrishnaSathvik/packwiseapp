import { interpretCapability } from "../../../src/capabilities/interpret.ts";
import { createHandler } from "../../../src/pipeline.ts";
import { runtime } from "../../../src/runtime.ts";

const { config, store, adapter, integrity } = runtime();

export default createHandler(interpretCapability, { config, store, adapter, integrity });
