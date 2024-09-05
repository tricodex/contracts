// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./interfaces/IOracle.sol";

/// @title GrandhardAgent
/// @notice This contract interacts with teeML oracle to run AI agents with dynamic system prompts
contract GrandhardAgent {
    // Structs
    struct AgentRun {
        address owner;
        IOracle.Message[] messages;
        uint responsesCount;
        uint8 max_iterations;
        bool is_finished;
    }

    // State variables
    mapping(uint => AgentRun) public agentRuns;
    uint private agentRunCount;
    address private owner;
    address public oracleAddress;
    IOracle.OpenAiRequest private config;

    // Events
    event AgentRunCreated(address indexed owner, uint indexed runId);
    event OracleAddressUpdated(address indexed newOracleAddress);

    // Constructor
    constructor(address initialOracleAddress) {
        owner = msg.sender;
        oracleAddress = initialOracleAddress;
        _initializeConfig();
    }

    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not owner");
        _;
    }

    modifier onlyOracle() {
        require(msg.sender == oracleAddress, "Caller is not oracle");
        _;
    }

    // Functions
    function _initializeConfig() private {
        config = IOracle.OpenAiRequest({
            model: "gpt-4o-2024-08-06",
            frequencyPenalty: 21,
            logitBias: "",
            maxTokens: 1000,
            presencePenalty: 21,
            responseFormat: "{\"type\":\"json_object\"}",
            seed: 0,
            stop: "",
            temperature: 10,
            topP: 101,
            tools: "[{\"type\":\"function\",\"function\":{\"name\":\"web_search\",\"description\":\"Search the internet\",\"parameters\":{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"Search query\"}},\"required\":[\"query\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"image_generation\",\"description\":\"Generates an image using Dalle-2\",\"parameters\":{\"type\":\"object\",\"properties\":{\"prompt\":{\"type\":\"string\",\"description\":\"Dalle-2 prompt to generate an image\"}},\"required\":[\"prompt\"]}}}]",
            toolChoice: "auto",
            user: ""
        });
    }

    /// @notice Updates the oracle address
    /// @param newOracleAddress The new oracle address to set
    function setOracleAddress(address newOracleAddress) public onlyOwner {
        oracleAddress = newOracleAddress;
        emit OracleAddressUpdated(newOracleAddress);
    }

    /// @notice Starts a new agent run with a dynamic system prompt
    /// @param systemPrompt The system prompt for this specific run
    /// @param query The initial user query
    /// @param max_iterations The maximum number of iterations for the agent run
    /// @return The ID of the newly created agent run
    function runAgent(string memory systemPrompt, string memory query, uint8 max_iterations) public returns (uint) {
        AgentRun storage run = agentRuns[agentRunCount];

        run.owner = msg.sender;
        run.is_finished = false;
        run.responsesCount = 0;
        run.max_iterations = max_iterations;

        IOracle.Message memory systemMessage = createTextMessage("system", systemPrompt);
        run.messages.push(systemMessage);

        IOracle.Message memory newMessage = createTextMessage("user", query);
        run.messages.push(newMessage);

        uint currentId = agentRunCount;
        agentRunCount = agentRunCount + 1;

        IOracle(oracleAddress).createOpenAiLlmCall(currentId, config);
        emit AgentRunCreated(run.owner, currentId);

        return currentId;
    }

    /// @notice Handles the response from the oracle for an OpenAI LLM call
    /// @dev Called by teeML oracle
    function onOracleOpenAiLlmResponse(
        uint runId,
        IOracle.OpenAiResponse memory response,
        string memory errorMessage
    ) public onlyOracle {
        AgentRun storage run = agentRuns[runId];

        if (bytes(errorMessage).length > 0) {
            IOracle.Message memory newMessage = createTextMessage("assistant", errorMessage);
            run.messages.push(newMessage);
            run.responsesCount++;
            run.is_finished = true;
            return;
        }
        if (run.responsesCount >= run.max_iterations) {
            run.is_finished = true;
            return;
        }
        if (bytes(response.content).length > 0) {
            IOracle.Message memory newMessage = createTextMessage("assistant", response.content);
            run.messages.push(newMessage);
            run.responsesCount++;
        }
        if (bytes(response.functionName).length > 0) {
            IOracle(oracleAddress).createFunctionCall(runId, response.functionName, response.functionArguments);
            return;
        }
        run.is_finished = true;
    }

    /// @notice Handles the response from the oracle for a function call
    /// @dev Called by teeML oracle
    function onOracleFunctionResponse(
        uint runId,
        string memory response,
        string memory errorMessage
    ) public onlyOracle {
        AgentRun storage run = agentRuns[runId];
        require(!run.is_finished, "Run is finished");

        string memory result = bytes(errorMessage).length > 0 ? errorMessage : response;

        IOracle.Message memory newMessage = createTextMessage("user", result);
        run.messages.push(newMessage);
        run.responsesCount++;
        IOracle(oracleAddress).createOpenAiLlmCall(runId, config);
    }

    /// @notice Retrieves the message history for a given agent run
    /// @param agentId The ID of the agent run
    /// @return An array of messages
    function getMessageHistory(uint agentId) public view returns (IOracle.Message[] memory) {
        return agentRuns[agentId].messages;
    }

    /// @notice Checks if a given agent run is finished
    /// @param runId The ID of the agent run
    /// @return True if the run is finished, false otherwise
    function isRunFinished(uint runId) public view returns (bool) {
        return agentRuns[runId].is_finished;
    }

    /// @notice Creates a text message with the given role and content
    /// @param role The role of the message
    /// @param content The content of the message
    /// @return The created message
    function createTextMessage(string memory role, string memory content) private pure returns (IOracle.Message memory) {
        IOracle.Message memory newMessage = IOracle.Message({
            role: role,
            content: new IOracle.Content[](1)
        });
        newMessage.content[0].contentType = "text";
        newMessage.content[0].value = content;
        return newMessage;
    }
}