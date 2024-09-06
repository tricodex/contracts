import { Contract, ethers, TransactionReceipt, Wallet } from "ethers";
import { abi as ABI } from "./abis/SPAgentOracleCompliant.json";
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
    const contractAddress = process.env.ORACLE_COMPLIANT_SP_AGENT_CONTRACT_ADDRESS;

    if (!rpcUrl || !privateKey || !contractAddress) {
        throw Error("Missing required environment variables. Check your .env file.");
    }

    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new Wallet(privateKey, provider);
    const contract = new Contract(contractAddress, ABI, wallet);

    console.log(`Connected. Contract address: ${contractAddress}`);

    const currentPrompt = await contract.prompt();
    console.log(`Current system prompt: "${currentPrompt}"`);

    if ((await getUserInput("Change system prompt? (y/n): ")).toLowerCase() === 'y') {
        const newSystemPrompt = await getUserInput("New system prompt: ");
        const setPromptTx = await contract.setSystemPrompt(newSystemPrompt);
        console.log(`Setting prompt, tx hash: ${setPromptTx.hash}`);
        await setPromptTx.wait();
        await new Promise(resolve => setTimeout(resolve, 5000));
        const updatedPrompt = await contract.prompt();
        console.log(`New system prompt: "${updatedPrompt}"`);
    }

    const query = await getUserInput("Agent's task: ") || "create an agentic framework and flow";
    const maxIterations = Number(await getUserInput("Max iterations: ") || "5");

    console.log("Running agent...");
    const runAgentTx = await contract.runAgent(query, maxIterations);
    const receipt = await runAgentTx.wait();
    console.log(`Task sent, tx hash: ${receipt.hash}`);

    const agentRunID = getAgentRunId(receipt, contract);
    if (agentRunID === undefined) {
        console.error("Failed to get agent run ID. Exiting.");
        return;
    }
    console.log(`Agent run ID: ${agentRunID}`);

    let allMessages: Message[] = [];
    let exitNextLoop = false;
    let noNewMessageCount = 0;
    while (true) {
        const newMessages = await getNewMessages(contract, agentRunID, allMessages.length);
        if (newMessages.length > 0) {
            noNewMessageCount = 0;
            for (const message of newMessages) {
                const roleDisplay = message.role === 'assistant' ? 'THOUGHT' : 'STEP';
                const color = message.role === 'assistant' ? '\x1b[36m' : '\x1b[33m';
                console.log(`${color}${roleDisplay}\x1b[0m: ${message.content}`);
                allMessages.push(message);
            }
        } else {
            noNewMessageCount++;
            if (noNewMessageCount <= 3) {
                console.log("No new messages.");
            } else if (noNewMessageCount % 5 === 0) {
                console.log(`Still waiting... (${noNewMessageCount} checks)`);
            }
        }

        if (exitNextLoop) {
            console.log(`Agent run ID ${agentRunID} finished!`);
            break;
        }

        const isFinished = await contract.isRunFinished(agentRunID);
        if (isFinished) {
            console.log("Agent run marked as finished. Exiting after next check.");
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
    const messages = await contract.getMessageHistory(agentRunID);
    return messages.slice(currentMessagesCount).map((message: any) => ({
        role: message.role,
        content: message.content[0].value,
    }));
}

main()
    .then(() => console.log("Script completed successfully."))
    .catch((error) => {
        console.error("An error occurred:", error);
        process.exit(1);
    });