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

        const choice = await getUserInput("Enter your choice (1-3) [1]: ", "1");

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
    const query = await getUserInput("Enter your initial query [What is the capital of France?]: ", "What is the capital of France?");
    const interactionType = await getInteractionType();
    const maxIterations = await getMaxIterations();
    const systemPrompt = await getUserInput("Enter system prompt [You are a helpful assistant.]: ", "You are a helpful assistant.");
    const useMemory = await getUseMemory();
    const knowledgeBaseCID = await getUserInput("Enter knowledge base CID (leave empty if not using): ", "");

    console.log("\nStarting a new agent run...");
    const transactionResponse = await contract.startAgentRun(query, interactionType, maxIterations, systemPrompt, useMemory, knowledgeBaseCID);
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
                    const userMessage = await getUserInput("\nYour response (or press Enter to end the conversation): ");
                    if (userMessage.trim() === "") {
                        isFinished = true;
                        break;
                    }
                    await contract.addUserMessage(runId, userMessage);
                    console.log("Message sent to the agent.");
                }
            }
        }

        if (!isFinished) {
            isFinished = await contract.isRunFinished(runId);
            if (!isFinished) {
                await new Promise(resolve => setTimeout(resolve, 2000));
            }
        }
    }

    console.log("\nAgent run completed.");
}

async function updateConfiguration(contract: Contract) {
    console.log("\nUpdating configuration...");
    const model = await getUserInput("Enter model (gpt-4o): ", "gpt-4o");
    const maxTokens = parseInt(await getUserInput("Enter max tokens (1000): ", "1000"));
    const temperature = parseFloat(await getUserInput("Enter temperature (0.1-1.0) [0.7]: ", "0.7")) * 10;
    const topP = parseFloat(await getUserInput("Enter top_p (0.0-1.0) [1.0]: ", "1.0")) * 100;

    const config = {
        model,
        frequencyPenalty: 21,
        logitBias: "",
        maxTokens,
        presencePenalty: 21,
        responseFormat: "{\"type\":\"text\"}",
        seed: 0,
        stop: "",
        temperature,
        topP,
        tools: "[{\"type\":\"function\",\"function\":{\"name\":\"web_search\",\"description\":\"Search the internet\",\"parameters\":{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"Search query\"}},\"required\":[\"query\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"image_generation\",\"description\":\"Generates an image using Dalle-2\",\"parameters\":{\"type\":\"object\",\"properties\":{\"prompt\":{\"type\":\"string\",\"description\":\"Dalle-2 prompt to generate an image\"}},\"required\":[\"prompt\"]}}}]",
        toolChoice: "auto",
        user: ""
    };

    await contract.updateConfig(config);
    console.log("Configuration updated successfully.");
}

async function getUserInput(prompt: string, defaultValue: string = ""): Promise<string> {
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout
    });

    return new Promise((resolve) => {
        rl.question(prompt, (answer) => {
            rl.close();
            resolve(answer.trim() || defaultValue);
        });
    });
}

async function getInteractionType(): Promise<InteractionType> {
    console.log("\nChoose an interaction type:");
    console.log("0. Single Response (default)");
    console.log("1. Chain of Thought");
    console.log("2. Chat");
    console.log("3. Collaborative");

    const choice = await getUserInput("Enter your choice (0-3) [0]: ", "0");
    const numChoice = parseInt(choice);
    return numChoice >= 0 && numChoice <= 3 ? numChoice : InteractionType.SingleResponse;
}

async function getMaxIterations(): Promise<number> {
    const input = await getUserInput("Enter the maximum number of iterations (1-10) [3]: ", "3");
    const numInput = parseInt(input);
    return numInput >= 1 && numInput <= 10 ? numInput : 3;
}

async function getUseMemory(): Promise<boolean> {
    const input = await getUserInput("Use memory? (y/n) [n]: ", "n");
    return input.toLowerCase() === 'y';
}

function getRunId(receipt: TransactionReceipt, contract: Contract): number | undefined {
    for (const log of receipt.logs) {
        try {
            const parsedLog = contract.interface.parseLog(log);
            if (parsedLog && parsedLog.name === "AgentRunCreated") {
                return ethers.toNumber(parsedLog.args[0]);
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