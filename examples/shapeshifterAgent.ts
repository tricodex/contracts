import { Contract, ethers, TransactionReceipt, Wallet } from "ethers";
import { abi as ABI } from "./abis/ShapeshifterAgent.json";
import * as readline from 'readline';
import dotenv from 'dotenv';

dotenv.config();

interface Message {
    role: string;
    content: string;
}

enum InteractionType {
    SingleResponse,
    ChainOfThought,
    Chat,
    Collaborative
}

async function main() {
    const rpcUrl = process.env.RPC_URL;
    if (!rpcUrl) throw Error("Missing RPC_URL in .env");

    const privateKey = process.env.PRIVATE_KEY;
    if (!privateKey) throw Error("Missing PRIVATE_KEY in .env");

    const contractAddress = process.env.SHAPESHIFTER_AGENT_ADDRESS;
    if (!contractAddress) throw Error("Missing SHAPESHIFTER_AGENT_ADDRESS in .env");

    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new Wallet(privateKey, provider);
    const contract = new Contract(contractAddress, ABI, wallet);

    console.log("Welcome to the ShapeshifterAgent CLI!");
    console.log("----------------------------------------");

    while (true) {
        console.log("\nChoose an action:");
        console.log("1. Start a new agent run");
        console.log("2. Update configuration");
        console.log("3. Exit");

        const choice = await getUserInput("Enter your choice (1-3): ");

        if (choice === "1") {
            await startNewAgentRun(contract);
        } else if (choice === "2") {
            await updateConfiguration(contract);
        } else if (choice === "3") {
            console.log("Exiting the CLI. Goodbye!");
            break;
        } else {
            console.log("Invalid choice. Please try again.");
        }
    }
}

async function startNewAgentRun(contract: Contract) {
    const query = await getUserInput("Enter your initial query: ");
    const interactionType = await getInteractionType();
    const maxIterations = await getMaxIterations();
    const systemPrompt = await getUserInput("Enter the system prompt: ");
    const useMemory = (await getUserInput("Use memory? (y/n): ")).toLowerCase() === 'y';
    const knowledgeBaseCID = await getUserInput("Enter knowledge base CID (leave empty if not using): ");

    console.log("\nStarting a new agent run...");
    const transactionResponse = await contract.startAgentRun(
        query,
        interactionType,
        maxIterations,
        systemPrompt,
        useMemory,
        knowledgeBaseCID
    );
    const receipt = await transactionResponse.wait();
    
    console.log(`Transaction sent, hash: ${receipt.hash}`);
    
    const runId = getRunId(receipt, contract);
    if (runId === undefined) {
        console.log("Failed to get run ID. Aborting.");
        return;
    }
    console.log(`Created agent run with ID: ${runId}`);

    await handleAgentRun(contract, runId, interactionType);
}

async function handleAgentRun(contract: Contract, runId: number, interactionType: InteractionType) {
    let isFinished = false;
    let messageCount = 0;

    while (!isFinished) {
        const newMessages = await getNewMessages(contract, runId, messageCount);
        
        for (const message of newMessages) {
            console.log(`\n${message.role.toUpperCase()}: ${message.content}`);
            messageCount++;

            if (message.role === "assistant") {
                if (interactionType === InteractionType.Chat || interactionType === InteractionType.Collaborative) {
                    const userMessage = await getUserInput("\nYour response: ");
                    await contract.addUserMessage(runId, userMessage);
                    console.log("Message sent to the agent.");
                }
            }
        }

        isFinished = await contract.isRunFinished(runId);
        if (!isFinished) {
            await new Promise(resolve => setTimeout(resolve, 2000));
        }
    }

    console.log("\nAgent run completed.");
}

async function updateConfiguration(contract: Contract) {
    console.log("\nUpdating configuration...");
    const model = await getUserInput("Enter model (e.g., gpt-4o): ");
    const maxTokens = parseInt(await getUserInput("Enter max tokens: "));
    const temperature = parseInt(await getUserInput("Enter temperature (0-20): ")) * 10;
    const tools = await getUserInput("Enter tools JSON (or leave empty): ");

    const newConfig = {
        model,
        frequencyPenalty: 21,
        logitBias: "",
        maxTokens,
        presencePenalty: 21,
        responseFormat: "{\"type\":\"text\"}",
        seed: 0,
        stop: "",
        temperature,
        topP: 101,
        tools,
        toolChoice: "auto",
        user: ""
    };

    await contract.updateConfig(newConfig);
    console.log("Configuration updated successfully.");
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

async function getInteractionType(): Promise<InteractionType> {
    console.log("\nChoose an interaction type:");
    console.log("0. Single Response");
    console.log("1. Chain of Thought");
    console.log("2. Chat");
    console.log("3. Collaborative");

    while (true) {
        const choice = await getUserInput("Enter your choice (0-3): ");
        const numChoice = parseInt(choice);
        if (numChoice >= 0 && numChoice <= 3) {
            return numChoice;
        }
        console.log("Invalid choice. Please try again.");
    }
}

async function getMaxIterations(): Promise<number> {
    while (true) {
        const input = await getUserInput("Enter the maximum number of iterations (1-10): ");
        const numInput = parseInt(input);
        if (numInput >= 1 && numInput <= 10) {
            return numInput;
        }
        console.log("Invalid input. Please enter a number between 1 and 10.");
    }
}

function getRunId(receipt: TransactionReceipt, contract: Contract): number | undefined {
    for (const log of receipt.logs) {
        try {
            const parsedLog = contract.interface.parseLog(log);
            if (parsedLog && parsedLog.name === "AgentRunCreated") {
                return ethers.toNumber(parsedLog.args[1]);
            }
        } catch (error) {
            console.log("Could not parse log:", log);
        }
    }
    return undefined;
}

async function getNewMessages(
    contract: Contract,
    runId: number,
    currentMessagesCount: number
): Promise<Message[]> {
    const messages = await contract.getAgentRunMessages(runId);
    return messages.slice(currentMessagesCount).map((message: any) => ({
        role: message.role,
        content: message.content[0].value
    }));
}

main().catch((error) => {
    console.error("An error occurred:", error);
    process.exit(1);
});