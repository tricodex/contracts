import { Contract, ethers, TransactionReceipt, Wallet } from "ethers";
import { abi as ABI } from "./abis/SSA.json";
import * as readline from 'readline';
import dotenv from 'dotenv';
import fs from 'fs';

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

function writeLog(message: string) {
    const timestamp = new Date().toISOString();
    const logMessage = `[${timestamp}] ${message}\n`;
    console.log(logMessage);
    fs.appendFileSync('shapeshifter_debug.log', logMessage);
}

async function main() {
    try {
        writeLog("Starting ShapeshifterAgent CLI");
        const rpcUrl = process.env.RPC_URL;
        if (!rpcUrl) throw Error("Missing RPC_URL in .env");

        const privateKey = process.env.PRIVATE_KEY;
        if (!privateKey) throw Error("Missing PRIVATE_KEY in .env");

        const contractAddress = process.env.SSA_CONTRACT_ADDRESS;
        if (!contractAddress) throw Error("Missing SSA_CONTRACT_ADDRESS in .env");

        writeLog(`Connecting to network: ${rpcUrl}`);
        const provider = new ethers.JsonRpcProvider(rpcUrl);
        const wallet = new Wallet(privateKey, provider);
        writeLog(`Wallet address: ${wallet.address}`);

        writeLog(`Initializing contract at address: ${contractAddress}`);
        const contract = new Contract(contractAddress, ABI, wallet);

        writeLog("ShapeshifterAgent CLI initialized successfully");
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
                writeLog("Exiting the CLI");
                console.log("Exiting the CLI. Goodbye!");
                break;
            } else {
                console.log("Invalid choice. Please try again.");
            }
        }
    } catch (error) {
        writeLog(`Fatal error: ${error}`);
        console.error("A fatal error occurred:", error);
        process.exit(1);
    }
}

async function startNewAgentRun(contract: Contract) {
    try {
        writeLog("Starting new agent run");
        const query = await getUserInput("Enter your initial query [What is the capital of France?]: ", "What is the capital of France?");
        const interactionType = await getInteractionType();
        const maxIterations = await getMaxIterations();
        const systemPrompt = await getUserInput("Enter system prompt [You are a helpful assistant.]: ", "You are a helpful assistant.");
        const useMemory = await getUseMemory();
        const knowledgeBaseCID = await getUserInput("Enter knowledge base CID (leave empty if not using): ", "");

        writeLog(`Query: ${query}`);
        writeLog(`Interaction Type: ${InteractionType[interactionType]}`);
        writeLog(`Max Iterations: ${maxIterations}`);
        writeLog(`System Prompt: ${systemPrompt}`);
        writeLog(`Use Memory: ${useMemory}`);
        writeLog(`Knowledge Base CID: ${knowledgeBaseCID}`);

        console.log("\nStarting a new agent run...");
        writeLog("Calling startAgentRun on contract");
        const transactionResponse = await contract.startAgentRun(query, interactionType, maxIterations, systemPrompt, useMemory, knowledgeBaseCID);
        writeLog(`Transaction sent: ${transactionResponse.hash}`);
        console.log(`Transaction sent, hash: ${transactionResponse.hash}`);

        writeLog("Waiting for transaction confirmation");
        const receipt = await transactionResponse.wait();
        writeLog(`Transaction confirmed in block ${receipt.blockNumber}`);
        
        const runId = getRunId(receipt, contract);
        if (runId === undefined) {
            writeLog("Failed to get run ID");
            console.log("Failed to get run ID. Aborting.");
            return;
        }
        writeLog(`Created agent run with ID: ${runId}`);
        console.log(`Created agent run with ID: ${runId}`);

        await handleAgentRun(contract, runId, interactionType);
    } catch (error) {
        writeLog(`Error in startNewAgentRun: ${error}`);
        console.error("An error occurred while starting the agent run:", error);
    }
}

async function handleAgentRun(contract: Contract, runId: number, interactionType: InteractionType) {
    try {
        writeLog(`Handling agent run ${runId}`);
        let isFinished = false;
        let messageCount = 0;
        let dotCount = 0;
        const startTime = Date.now();
        const timeoutDuration = 5 * 60 * 1000; // 5 minutes timeout

        console.log("\nWaiting for agent response");
        writeLog("Entering message polling loop");

        while (!isFinished) {
            try {
                const newMessages = await getNewMessages(contract, runId, messageCount);
                writeLog(`Received ${newMessages.length} new messages`);
                
                for (const message of newMessages) {
                    console.log(`\n${message.role.toUpperCase()}: ${message.content}`);
                    writeLog(`Message - Role: ${message.role}, Content: ${message.content}`);
                    messageCount++;

                    if (message.role === "assistant" && (interactionType === InteractionType.Chat || interactionType === InteractionType.Collaborative)) {
                        const userMessage = await getUserInput("\nYour response (or press Enter to end the conversation): ");
                        if (userMessage.trim() === "") {
                            writeLog("User ended the conversation");
                            isFinished = true;
                            break;
                        }
                        writeLog(`Sending user message: ${userMessage}`);
                        await contract.addUserMessage(runId, userMessage);
                        console.log("Message sent to the agent.");
                    }
                }

                if (!isFinished) {
                    isFinished = await contract.isRunFinished(runId);
                    writeLog(`Run finished status: ${isFinished}`);
                    if (!isFinished) {
                        process.stdout.write(".");
                        dotCount++;
                        if (dotCount % 10 === 0) {
                            process.stdout.write("\n");
                        }
                        await new Promise(resolve => setTimeout(resolve, 2000));

                        if (Date.now() - startTime > timeoutDuration) {
                            writeLog("Response timed out after 5 minutes");
                            console.log("\nResponse timed out after 5 minutes. The agent might still be processing.");
                            isFinished = true;
                        }
                    }
                }
            } catch (error) {
                writeLog(`Error in message polling loop: ${error}`);
                console.error("An error occurred while polling for messages:", error);
                await new Promise(resolve => setTimeout(resolve, 5000)); // Wait 5 seconds before retrying
            }
        }

        writeLog("Agent run completed or timed out");
        console.log("\nAgent run completed or timed out.");
    } catch (error) {
        writeLog(`Error in handleAgentRun: ${error}`);
        console.error("An error occurred while handling the agent run:", error);
    }
}

async function updateConfiguration(contract: Contract) {
    try {
        writeLog("Updating configuration");
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

        writeLog(`Updating contract config: ${JSON.stringify(config)}`);
        await contract.updateConfig(config);
        writeLog("Configuration updated successfully");
        console.log("Configuration updated successfully.");
    } catch (error) {
        writeLog(`Error in updateConfiguration: ${error}`);
        console.error("An error occurred while updating the configuration:", error);
    }
}

async function getUserInput(prompt: string, defaultValue: string = ""): Promise<string> {
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout
    });

    return new Promise((resolve) => {
        rl.question(prompt, (answer) => {
            rl.close();
            const result = answer.trim() || defaultValue;
            writeLog(`User input: ${prompt} -> ${result}`);
            resolve(result);
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
    const result = numChoice >= 0 && numChoice <= 3 ? numChoice : InteractionType.SingleResponse;
    writeLog(`Interaction type chosen: ${InteractionType[result]}`);
    return result;
}

async function getMaxIterations(): Promise<number> {
    const input = await getUserInput("Enter the maximum number of iterations (1-10) [3]: ", "3");
    const numInput = parseInt(input);
    const result = numInput >= 1 && numInput <= 10 ? numInput : 3;
    writeLog(`Max iterations: ${result}`);
    return result;
}

async function getUseMemory(): Promise<boolean> {
    const input = await getUserInput("Use memory? (y/n) [n]: ", "n");
    const result = input.toLowerCase() === 'y';
    writeLog(`Use memory: ${result}`);
    return result;
}

function getRunId(receipt: TransactionReceipt, contract: Contract): number | undefined {
    writeLog("Parsing transaction receipt for run ID");
    for (const log of receipt.logs) {
        try {
            const parsedLog = contract.interface.parseLog(log);
            if (parsedLog && parsedLog.name === "AgentRunCreated") {
                const runId = ethers.toNumber(parsedLog.args[0]);
                writeLog(`Found run ID: ${runId}`);
                return runId;
            }
        } catch (error) {
            writeLog(`Error parsing log: ${error}`);
        }
    }
    writeLog("Run ID not found in transaction receipt");
    return undefined;
}

async function getNewMessages(
    contract: Contract,
    runId: number,
    currentMessagesCount: number
): Promise<Message[]> {
    try {
        writeLog(`Fetching messages for run ${runId}, starting from index ${currentMessagesCount}`);
        const messages = await contract.getAgentRunMessages(runId);
        writeLog(`Total messages received: ${messages.length}`);
        const newMessages = messages.slice(currentMessagesCount).map((message: any) => ({
            role: message.role,
            content: message.content[0].value
        }));
        writeLog(`New messages: ${JSON.stringify(newMessages)}`);
        return newMessages;
    } catch (error) {
        writeLog(`Error fetching new messages: ${error}`);
        throw error;
    }
}

main().catch((error) => {
    writeLog(`Unhandled error in main: ${error}`);
    console.error("An unhandled error occurred:", error);
    process.exit(1);
});