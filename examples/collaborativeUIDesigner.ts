import { Contract, ethers, TransactionReceipt, Wallet } from "ethers";
import { abi as ABI } from "./abis/CollaborativeUIDesigner.json";
import * as readline from 'readline';
import * as dotenv from 'dotenv';

// Load environment variables
dotenv.config();

interface Message {
    role: string;
    content: string;
}

interface UIDesignStatus {
    currentStep: number;
    isComplete: boolean;
    projectName: string;
    complexity: number;
    currentDesignCID: string;
}

async function main() {
    console.log("Starting Collaborative UI Designer script...");

    // Validate environment variables
    const rpcUrl = process.env.RPC_URL;
    const privateKey = process.env.PRIVATE_KEY;
    const contractAddress = process.env.COLLABORATIVE_UI_DESIGNER_CONTRACT_ADDRESS;

    if (!rpcUrl) throw Error("Missing RPC_URL in .env");
    if (!privateKey) throw Error("Missing PRIVATE_KEY in .env");
    if (!contractAddress) throw Error("Missing COLLABORATIVE_UI_DESIGNER_CONTRACT_ADDRESS in .env");

    console.log("Environment variables loaded successfully.");

    // Set up provider, wallet, and contract instance
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new Wallet(privateKey, provider);
    const contract = new Contract(contractAddress, ABI, wallet);

    console.log("Ethereum provider, wallet, and contract instance set up.");

    // Get user inputs for the UI design project
    const projectName = await getUserInput("Project name: ");
    const projectDescription = await getUserInput("Project description: ");
    const initialKnowledgeBaseCID = await getUserInput("Initial knowledge base CID (leave empty if none): ");
    const maxIterations = await getUserInput("Max iterations: ");

    console.log("Starting new UI Design project...");

    try {
        // Start the UI design process
        const transactionResponse = await contract.startUIDesign(projectName, projectDescription, initialKnowledgeBaseCID, Number(maxIterations));
        const receipt = await transactionResponse.wait();
        console.log(`UI Design task sent, tx hash: ${receipt.hash}`);
        console.log(`UI Design started for project: "${projectName}"`);

        // Get the run ID from the transaction receipt
        let runId = getRunId(receipt, contract);
        if (runId === undefined) {
            throw new Error("Failed to get run ID from transaction receipt");
        }
        console.log(`Created UI Design run ID: ${runId}`);

        let allMessages: Message[] = [];
        let isRunning = true;

        while (isRunning) {
            // Fetch new messages
            const newMessages: Message[] = await getNewMessages(contract, runId, allMessages.length);
            if (newMessages.length > 0) {
                console.log(`Received ${newMessages.length} new message(s)`);
                for (let message of newMessages) {
                    let roleDisplay = message.role === 'assistant' ? 'AI' : message.role.toUpperCase();
                    let color = message.role === 'assistant' ? '\x1b[36m' : '\x1b[33m';
                    console.log(`${color}${roleDisplay}\x1b[0m: ${message.content}`);
                    allMessages.push(message);
                }
            }

            // Check if the run is finished
            const isFinished = await contract.isRunFinished(runId);
            if (isFinished) {
                console.log(`UI Design run ID ${runId} finished!`);
                isRunning = false;
                break;
            }

            // Get user input
            const userMessage = await getUserInput("Enter a message (or press Enter to skip): ");
            if (userMessage && userMessage.trim() !== "") {
                try {
                    await contract.addUserMessage(runId, userMessage);
                    console.log("User message sent successfully.");
                } catch (error) {
                    console.error("Error sending user message:", error);
                    if ((error as Error).message.includes("UI design process is already complete")) {
                        console.log("This design run is complete. Exiting...");
                        isRunning = false;
                    }
                }
            }

            // Wait before next iteration
            await new Promise(resolve => setTimeout(resolve, 2000));
        }

        // Display final UI Design status
        console.log("\nRetrieving final UI Design status...");
        const status = await getUIDesignStatus(contract, runId);
        console.log("\nFinal UI Design Status:");
        console.log(`Current Step: ${status.currentStep}`);
        console.log(`Is Complete: ${status.isComplete}`);
        console.log(`Project Name: ${status.projectName}`);
        console.log(`Complexity: ${status.complexity}`);
        console.log(`Current Design CID: ${status.currentDesignCID}`);

    } catch (error) {
        console.error("An error occurred during the UI Design process:", error);
    }
}

async function getUserInput(query: string): Promise<string> {
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout
    });

    return new Promise((resolve) => {
        rl.question(query, (answer) => {
            rl.close();
            resolve(answer);
        });
    });
}

function getRunId(receipt: TransactionReceipt, contract: Contract): number | undefined {
    let runId;
    for (const log of receipt.logs) {
        try {
            const parsedLog = contract.interface.parseLog(log);
            if (parsedLog && parsedLog.name === "UIDesignStarted") {
                runId = ethers.toNumber(parsedLog.args[1]);
                break;
            }
        } catch (error) {
            console.log("Could not parse log:", log);
        }
    }
    return runId;
}

async function getNewMessages(
    contract: Contract,
    runId: number,
    currentMessagesCount: number
): Promise<Message[]> {
    const messages = await contract.getMessageHistory(runId);
    const newMessages: Message[] = [];
    messages.forEach((message: any, i: number) => {
        if (i >= currentMessagesCount) {
            newMessages.push({
                role: message.role,
                content: message.content[0].value,
            });
        }
    });
    return newMessages;
}

async function getUIDesignStatus(contract: Contract, runId: number): Promise<UIDesignStatus> {
    try {
        const status = await contract.getUIDesignStatus(runId);
        return {
            currentStep: status.currentStep.toNumber(),
            isComplete: status.isComplete,
            projectName: status.projectName,
            complexity: status.complexity.toNumber(),
            currentDesignCID: status.currentDesignCID
        };
    } catch (error) {
        console.error("Error fetching UI Design status:", error);
        throw error;
    }
}

main()
    .then(() => console.log("Script executed successfully."))
    .catch((error) => {
        console.error("An unhandled error occurred:", error);
    });