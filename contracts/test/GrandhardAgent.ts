// test/GaladrielAgent.test.ts
import { expect } from "chai";
import { ethers } from "hardhat";
import { GaladrielAgent } from "../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

describe("GaladrielAgent", function () {
  let galadrielAgent: GaladrielAgent;
  let owner: SignerWithAddress;
  let addr1: SignerWithAddress;
  let oracle: SignerWithAddress;

  beforeEach(async function () {
    [owner, addr1, oracle] = await ethers.getSigners();

    const GaladrielAgent = await ethers.getContractFactory("GaladrielAgent");
    galadrielAgent = await GaladrielAgent.deploy(oracle.address, "You are a helpful AI agent");
    await galadrielAgent.deployed();
  });

  it("Should set the correct owner and oracle", async function () {
    expect(await galadrielAgent.owner()).to.equal(owner.address);
    expect(await galadrielAgent.oracleAddress()).to.equal(oracle.address);
  });

  it("Should create a new agent run", async function () {
    await expect(galadrielAgent.runAgent("Test query", 5))
      .to.emit(galadrielAgent, "AgentRunCreated")
      .withArgs(owner.address, 0);
  });

  it("Should process oracle responses", async function () {
    await galadrielAgent.runAgent("Test query", 5);
    
    const response = {
      id: "test",
      content: "Test response",
      functionName: "",
      functionArguments: "",
      created: 0,
      model: "gpt-4",
      systemFingerprint: "",
      object: "",
      completionTokens: 0,
      promptTokens: 0,
      totalTokens: 0
    };

    await expect(galadrielAgent.connect(oracle).onOracleOpenAiLlmResponse(0, response, ""))
      .to.emit(galadrielAgent, "AgentResponseReceived")
      .withArgs(0, "Test response");
  });

  // Add more tests as needed
});