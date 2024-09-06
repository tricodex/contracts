import { Contract, ethers, TransactionReceipt, Wallet } from "ethers";
import { abi as ABI } from "./abis/SPAgent.json";
import * as readline from 'readline';
import * as dotenv from 'dotenv';

dotenv.config();

interface Message {
  role: string,
  content: string,
}

async function main() {
    console.log("Initializing SPAgent script...");

    const rpcUrl = process.env.RPC_URL;
    const privateKey = process.env.PRIVATE_KEY;
    const contractAddress = process.env.SP_AGENT_CONTRACT_ADDRESS;

    if (!rpcUrl || !privateKey || !contractAddress) {
        throw Error("Missing required environment variables. Check your .env file.");
    }

    console.log("Connecting to network...");
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new Wallet(privateKey, provider);
    const contract = new Contract(contractAddress, ABI, wallet);

    console.log("Connected. Contract address:", contractAddress);

    const systemPrompt = await getUserInput(`Enter system prompt (default: "only respond in json"): `) || "only respond in json";

    console.log("Setting system prompt...");
    const setPromptTx = await contract.setSystemPrompt(systemPrompt);
    console.log("Transaction sent. Waiting for confirmation...");
    const setPromptReceipt = await setPromptTx.wait();
    console.log(`System prompt set. Transaction hash: ${setPromptReceipt.hash}`);

    console.log("Waiting for 5 seconds to ensure transaction is processed...");
    await new Promise(resolve => setTimeout(resolve, 5000));

    const currentPrompt = await contract.prompt();
    console.log(`Verified system prompt: "${currentPrompt}"`);

    if (currentPrompt !== systemPrompt) {
        console.warn("Warning: System prompt may not be set correctly.");
    }

    const query = await getUserInput(`Enter agent's task (default: "create an agentic framework and flow"): `) || "create an agentic framework and flow";
    const maxIterations = Number(await getUserInput("Enter max iterations (default: 5): ") || "5");

    console.log("Running agent...");
    const runAgentTx = await contract.runAgent(query, maxIterations);
    console.log("Transaction sent. Waiting for confirmation...");
    const receipt = await runAgentTx.wait();
    console.log(`Task sent, tx hash: ${receipt.hash}`);
    console.log(`Agent started with task: "${query}"`);

    const agentRunID = getAgentRunId(receipt, contract);
    if (agentRunID === undefined) {
        console.error("Failed to get agent run ID. Exiting.");
        return;
    }
    console.log(`Created agent run ID: ${agentRunID}`);

    console.log("Waiting for agent responses...");
    let allMessages: Message[] = [];
    let exitNextLoop = false;
    while (true) {
        const newMessages = await getNewMessages(contract, agentRunID, allMessages.length);
        if (newMessages.length > 0) {
            console.log(`Received ${newMessages.length} new message(s)`);
            for (const message of newMessages) {
                const roleDisplay = message.role === 'assistant' ? 'THOUGHT' : 'STEP';
                const color = message.role === 'assistant' ? '\x1b[36m' : '\x1b[33m';
                console.log(`${color}${roleDisplay}\x1b[0m: ${message.content}`);
                allMessages.push(message);
            }
        } else {
            console.log("No new messages. Checking if run is finished...");
        }

        if (exitNextLoop) {
            console.log(`Agent run ID ${agentRunID} finished!`);
            break;
        }

        const isFinished = await contract.isRunFinished(agentRunID);
        if (isFinished) {
            console.log("Agent run is marked as finished. Will exit after next iteration.");
            exitNextLoop = true;
        }

        await new Promise(resolve => setTimeout(resolve, 2000));
    }
}

async function getUserInput(prompt: string): Promise<string> {
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout
    });

    return new Promise((resolve) => {
        rl.question(prompt, (answer) => {
            rl.close();
            resolve(answer);
        });
    });
}

function getAgentRunId(receipt: TransactionReceipt, contract: Contract): number | undefined {
    for (const log of receipt.logs) {
        try {
            const parsedLog = contract.interface.parseLog(log);
            if (parsedLog && parsedLog.name === "AgentRunCreated") {
                return ethers.toNumber(parsedLog.args[1]);
            }
        } catch (error) {
            console.warn("Could not parse log:", log);
        }
    }
    return undefined;
}

async function getNewMessages(
    contract: Contract,
    agentRunID: number,
    currentMessagesCount: number
): Promise<Message[]> {
    console.log(`Fetching messages for run ID ${agentRunID}, starting from index ${currentMessagesCount}`);
    const messages = await contract.getMessageHistory(agentRunID);
    console.log(`Total messages in history: ${messages.length}`);

    const newMessages = messages.slice(currentMessagesCount).map((message: any) => ({
        role: message.role,
        content: message.content[0].value,
    }));
    console.log(`New messages found: ${newMessages.length}`);
    return newMessages;
}

main()
    .then(() => console.log("Script completed successfully."))
    .catch((error) => {
        console.error("An error occurred:", error);
        process.exit(1);
    });