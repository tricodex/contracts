// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./interfaces/IOracle.sol";

contract SSA {
    address public owner;
    address public oracleAddress;
    IOracle.OpenAiRequest public config;

    enum InteractionType { SingleResponse, ChainOfThought, Chat, Collaborative }

    struct AgentRun {
        address requester;
        InteractionType interactionType;
        uint8 maxIterations;
        uint currentIteration;
        IOracle.Message[] messages;
        bool isFinished;
        string systemPrompt;
        bool useMemory;
        string knowledgeBaseCID;
    }

    mapping(uint => AgentRun) public agentRuns;
    uint private runCount;

    event AgentRunCreated(uint indexed runId, address indexed requester, InteractionType interactionType);
    event ResponseReceived(uint indexed runId, string response);
    event ToolCallInitiated(uint indexed runId, string toolName);

    constructor(address _oracleAddress) {
        owner = msg.sender;
        oracleAddress = _oracleAddress;

        // Default configuration
        config = IOracle.OpenAiRequest({
            model: "gpt-4o",
            frequencyPenalty: 21,
            logitBias: "",
            maxTokens: 1000,
            presencePenalty: 21,
            responseFormat: "{\"type\":\"text\"}",
            seed: 0,
            stop: "",
            temperature: 10,
            topP: 101,
            tools: "[{\"type\":\"function\",\"function\":{\"name\":\"web_search\",\"description\":\"Search the internet\",\"parameters\":{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"Search query\"}},\"required\":[\"query\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"image_generation\",\"description\":\"Generates an image using Dalle-2\",\"parameters\":{\"type\":\"object\",\"properties\":{\"prompt\":{\"type\":\"string\",\"description\":\"Dalle-2 prompt to generate an image\"}},\"required\":[\"prompt\"]}}}]",
            toolChoice: "auto",
            user: ""
        });
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlyOracle() {
        require(msg.sender == oracleAddress, "Only oracle can call this function");
        _;
    }

    function updateConfig(IOracle.OpenAiRequest memory _newConfig) public onlyOwner {
        config = _newConfig;
    }

    function setOracleAddress(address _newOracleAddress) public onlyOwner {
        oracleAddress = _newOracleAddress;
    }

    function startAgentRun(
        string memory query,
        InteractionType interactionType,
        uint8 maxIterations,
        string memory systemPrompt,
        bool useMemory,
        string memory knowledgeBaseCID
    ) public returns (uint) {
        uint runId = runCount++;
        AgentRun storage run = agentRuns[runId];

        run.requester = msg.sender;
        run.interactionType = interactionType;
        run.maxIterations = maxIterations;
        run.currentIteration = 0;
        run.isFinished = false;
        run.systemPrompt = systemPrompt;
        run.useMemory = useMemory;
        run.knowledgeBaseCID = knowledgeBaseCID;

        _addMessageToRun(run, "system", systemPrompt);
        _addMessageToRun(run, "user", query);

        if (bytes(knowledgeBaseCID).length > 0) {
            IOracle(oracleAddress).createKnowledgeBaseQuery(runId, knowledgeBaseCID, query, 3);
        } else {
            IOracle(oracleAddress).createOpenAiLlmCall(runId, config);
        }

        emit AgentRunCreated(runId, msg.sender, interactionType);
        return runId;
    }

    function onOracleOpenAiLlmResponse(
        uint runId,
        IOracle.OpenAiResponse memory response,
        string memory errorMessage
    ) public onlyOracle {
        AgentRun storage run = agentRuns[runId];

        if (bytes(errorMessage).length > 0) {
            _addMessageToRun(run, "assistant", errorMessage);
            run.isFinished = true;
            emit ResponseReceived(runId, errorMessage);
            return;
        }

        if (bytes(response.functionName).length > 0) {
            IOracle(oracleAddress).createFunctionCall(runId, response.functionName, response.functionArguments);
            emit ToolCallInitiated(runId, response.functionName);
            return;
        }

        _addMessageToRun(run, "assistant", response.content);
        emit ResponseReceived(runId, response.content);

        run.currentIteration++;

        if (run.currentIteration >= run.maxIterations || 
            run.interactionType == InteractionType.SingleResponse) {
            run.isFinished = true;
        } else if (run.interactionType == InteractionType.ChainOfThought) {
            _addMessageToRun(run, "user", "Continue your chain of thought.");
            IOracle(oracleAddress).createOpenAiLlmCall(runId, config);
        }
    }

    function onOracleKnowledgeBaseQueryResponse(
        uint runId,
        string[] memory documents,
        string memory errorMessage
    ) public onlyOracle {
        AgentRun storage run = agentRuns[runId];

        if (bytes(errorMessage).length > 0) {
            _addMessageToRun(run, "system", errorMessage);
            run.isFinished = true;
            emit ResponseReceived(runId, errorMessage);
            return;
        }

        string memory context = "Relevant context:\n";
        for (uint i = 0; i < documents.length; i++) {
            context = string(abi.encodePacked(context, documents[i], "\n"));
        }

        _addMessageToRun(run, "system", context);
        IOracle(oracleAddress).createOpenAiLlmCall(runId, config);
    }

    function onOracleFunctionResponse(
        uint runId,
        string memory response,
        string memory errorMessage
    ) public onlyOracle {
        AgentRun storage run = agentRuns[runId];
        
        if (bytes(errorMessage).length > 0) {
            _addMessageToRun(run, "system", errorMessage);
        } else {
            _addMessageToRun(run, "function", response);
        }
        
        IOracle(oracleAddress).createOpenAiLlmCall(runId, config);
    }

    function addUserMessage(uint runId, string memory message) public {
        AgentRun storage run = agentRuns[runId];
        require(msg.sender == run.requester, "Only the run requester can add messages");
        require(!run.isFinished, "This run has finished");

        _addMessageToRun(run, "user", message);

        if (bytes(run.knowledgeBaseCID).length > 0) {
            IOracle(oracleAddress).createKnowledgeBaseQuery(runId, run.knowledgeBaseCID, message, 3);
        } else {
            IOracle(oracleAddress).createOpenAiLlmCall(runId, config);
        }
    }

    function getAgentRunMessages(uint runId) public view returns (IOracle.Message[] memory) {
        return agentRuns[runId].messages;
    }

    function isRunFinished(uint runId) public view returns (bool) {
        return agentRuns[runId].isFinished;
    }

    function _addMessageToRun(AgentRun storage run, string memory role, string memory content) internal {
        IOracle.Content[] memory messageContent = new IOracle.Content[](1);
        messageContent[0] = IOracle.Content({contentType: "text", value: content});
        run.messages.push(IOracle.Message({
            role: role,
            content: messageContent
        }));
    }
}