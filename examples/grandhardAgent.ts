import { Contract, ethers, TransactionReceipt, Wallet } from "ethers";
import { abi as ABI } from "./abis/GrandhardAgent.json";
import * as readline from 'readline';
import * as dotenv from 'dotenv';

dotenv.config();

// Define the structure of a message
interface Message {
    role: string;
    content: string;
}

// Main function to initialize the script and handle the contract interaction
async function main() {
    console.log("Starting the GrandhardAgent script...");

    // Retrieve environment variables for RPC URL, private key, and contract address
    const rpcUrl = process.env.RPC_URL;
    if (!rpcUrl) throw Error("Missing RPC_URL in .env");

    const privateKey = process.env.PRIVATE_KEY;
    if (!privateKey) throw Error("Missing PRIVATE_KEY in .env");

    const contractAddress = process.env.GRANDHARD_AGENT_CONTRACT_ADDRESS;
    if (!contractAddress) throw Error("Missing GRANDHARD_AGENT_CONTRACT_ADDRESS in .env");

    // Initialize Ethereum provider and wallet
    console.log("Initializing provider and wallet...");
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const wallet = new Wallet(privateKey, provider);

    // Create a contract instance
    console.log("Creating contract instance...");
    const contract = new Contract(contractAddress, ABI, wallet);

    // Get user inputs for the system prompt, query, and max iterations
    console.log("Getting user inputs...");
    const systemPrompt = await getUserInput("System prompt: ");
    const query = await getUserInput("Initial query: ");
    const maxIterations = await getUserInput("Max iterations: ");

    // Call the contract function to start the agent
    console.log("Calling runAgent function...");
    const transactionResponse = await contract.runAgent(systemPrompt, query, Number(maxIterations));

    // Wait for the transaction to be confirmed
    console.log("Waiting for transaction confirmation...");
    const receipt = await transactionResponse.wait();
    console.log(`Task sent, tx hash: ${receipt.hash}`);
    console.log(`Agent started with task: "${query}"`);

    // Retrieve the agent run ID from the transaction receipt
    console.log("Getting agent run ID...");
    let agentRunID = getAgentRunId(receipt, contract);
    console.log(`Created agent run ID: ${agentRunID}`);

    if (!agentRunID && agentRunID !== 0) {
        console.log("Failed to get agent run ID. Exiting...");
        return;
    }

    // Poll for new messages and check if the agent run is finished
    let allMessages: Message[] = [];
    let retryCount = 0;
    const maxRetries = 1000;
    const pollingInterval = 10000; // 10 seconds

    console.log("Starting main loop to fetch messages...");
    while (true) {
        console.log(`Fetching new messages for run ID ${agentRunID}...`);
        const newMessages: Message[] = await getNewMessages(contract, agentRunID, allMessages.length);

        // Process and display new messages
        if (newMessages.length > 0) {
            console.log(`Received ${newMessages.length} new message(s).`);
            for (let message of newMessages) {
                let roleDisplay = message.role === 'assistant' ? 'THOUGHT' : 'STEP';
                let color = message.role === 'assistant' ? '\x1b[36m' : '\x1b[33m'; // Cyan for thought, yellow for step
                console.log(`${color}${roleDisplay}\x1b[0m: ${message.content}`);
                allMessages.push(message);
            }
            retryCount = 0; // Reset retry count if new messages are received
        } else {
            retryCount++;
            console.log(`No new messages. Retry count: ${retryCount}`);
        }

        // Check if the agent run has finished
        console.log("Checking if run is finished...");
        const isFinished = await contract.isRunFinished(agentRunID);
        if (isFinished) {
            console.log(`Agent run ID ${agentRunID} finished!`);
            break;
        }

        // Terminate if the maximum retries have been reached
        if (retryCount >= maxRetries) {
            console.log("Max retries reached. Terminating.");
            break;
        }

        // Wait before polling again
        console.log(`Waiting for ${pollingInterval / 1000} seconds before next check...`);
        await new Promise(resolve => setTimeout(resolve, pollingInterval));
    }

    console.log("Script execution completed.");
}

// Function to get user input from the console
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

// Function to extract the agent run ID from the transaction receipt logs
function getAgentRunId(receipt: TransactionReceipt, contract: Contract): number | undefined {
    let agentRunID;
    for (const log of receipt.logs) {
        try {
            const parsedLog = contract.interface.parseLog(log);
            if (parsedLog && parsedLog.name === "AgentRunCreated") {
                agentRunID = ethers.toNumber(parsedLog.args[1]);
                break;
            }
        } catch (error) {
            console.log("Could not parse log:", log);
        }
    }
    return agentRunID;
}

// Function to fetch new messages from the contract based on the agent run ID
async function getNewMessages(
    contract: Contract,
    agentRunID: number,
    currentMessagesCount: number
): Promise<Message[]> {
    console.log(`Fetching message history for run ID ${agentRunID}...`);
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

// Execute the main function
main()
    .then(() => console.log("Script executed successfully."))
    .catch((error) => console.error("An error occurred:", error));