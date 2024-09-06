import {Contract, ethers, TransactionReceipt, Wallet} from "ethers";
import ABI from "./abis/Agent.json";
import * as readline from 'readline';
require("dotenv").config();

interface Message {
  role: string,
  content: string,
}

async function main() {
  console.log("Initializing Agent script...");

  const rpcUrl = process.env.RPC_URL;
  if (!rpcUrl) throw Error("Missing RPC_URL in .env");

  const privateKey = process.env.PRIVATE_KEY;
  if (!privateKey) throw Error("Missing PRIVATE_KEY in .env");

  const contractAddress = process.env.AGENT_CONTRACT_ADDRESS;
  if (!contractAddress) throw Error("Missing AGENT_CONTRACT_ADDRESS in .env");

  console.log("Connecting to network...");
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new Wallet(privateKey, provider);
  const contract = new Contract(contractAddress, ABI, wallet);

  console.log("Connected. Contract address:", contractAddress);

  // The query you want to start the agent with
  const query = await getUserInput("Agent's task: ");
  const maxIterations = await getUserInput("Max iterations: ");

  console.log("Running agent...");
  // Call the runAgent function
  const transactionResponse = await contract.runAgent(query, Number(maxIterations));
  console.log("Transaction sent. Waiting for confirmation...");
  const receipt = await transactionResponse.wait();
  console.log(`Task sent, tx hash: ${receipt.hash}`);
  console.log(`Agent started with task: "${query}"`);

  // Get the agent run ID from transaction receipt logs
  let agentRunID = getAgentRunId(receipt, contract);
  console.log(`Created agent run ID: ${agentRunID}`);
  if (!agentRunID && agentRunID !== 0) {
    console.error("Failed to get agent run ID. Exiting.");
    return;
  }

  console.log("Waiting for agent responses...");
  let allMessages: Message[] = [];
  // Run the chat loop: read messages and send messages
  let exitNextLoop = false;
  while (true) {
    const newMessages: Message[] = await getNewMessages(contract, agentRunID, allMessages.length);
    if (newMessages.length > 0) {
      console.log(`Received ${newMessages.length} new message(s)`);
      for (let message of newMessages) {
        let roleDisplay = message.role === 'assistant' ? 'THOUGHT' : 'STEP';
        let color = message.role === 'assistant' ? '\x1b[36m' : '\x1b[33m'; // Cyan for thought, yellow for step
        console.log(`${color}${roleDisplay}\x1b[0m: ${message.content}`);
        allMessages.push(message);
      }
    } else {
      console.log("No new messages. Checking if run is finished...");
    }

    await new Promise(resolve => setTimeout(resolve, 2000));

    if (exitNextLoop) {
      console.log(`Agent run ID ${agentRunID} finished!`);
      break;
    }

    const isFinished = await contract.isRunFinished(agentRunID);
    if (isFinished) {
      console.log("Agent run is marked as finished. Will exit after next iteration.");
      exitNextLoop = true;
    }
  }
}

async function getUserInput(query: string): Promise<string> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });

  const question = (query: string): Promise<string> => {
    return new Promise((resolve) => {
      rl.question(query, (answer) => {
        resolve(answer);
      });
    });
  };

  try {
    const input = await question(query);
    rl.close();
    return input;
  } catch (err) {
    console.error('Error getting user input:', err);
    rl.close();
    throw err;
  }
}

function getAgentRunId(receipt: TransactionReceipt, contract: Contract): number | undefined {
  let agentRunID;
  for (const log of receipt.logs) {
    try {
      const parsedLog = contract.interface.parseLog(log);
      if (parsedLog && parsedLog.name === "AgentRunCreated") {
        // Second event argument
        agentRunID = ethers.toNumber(parsedLog.args[1]);
        break;
      }
    } catch (error) {
      console.warn("Could not parse log:", log);
    }
  }
  return agentRunID;
}

async function getNewMessages(
  contract: Contract,
  agentRunID: number,
  currentMessagesCount: number
): Promise<Message[]> {
  console.log(`Fetching messages for run ID ${agentRunID}, starting from index ${currentMessagesCount}`);
  const messages = await contract.getMessageHistory(agentRunID);
  console.log(`Total messages in history: ${messages.length}`);

  const newMessages: Message[] = [];
  messages.forEach((message: any, i: number) => {
    if (i >= currentMessagesCount) {
      newMessages.push({
        role: message.role,
        content: message.content[0].value,
      });
    }
  });
  console.log(`New messages found: ${newMessages.length}`);
  return newMessages;
}

main()
  .then(() => console.log("Script completed successfully."))
  .catch((error) => {
    console.error("An error occurred:", error);
    process.exit(1);
  });