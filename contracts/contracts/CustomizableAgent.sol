// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./interfaces/IOracle.sol";

contract CustomizableAgent {
    address public owner;
    address public oracleAddress;
    IOracle.OpenAiRequest public config;
    string public systemPrompt;

    enum InteractionType { SingleResponse, ChainOfThought, Chat, Collaborative }

    struct AgentRun {
        address requester;
        InteractionType interactionType;
        uint8 maxIterations;
        uint currentIteration;
        IOracle.Message[] messages;
        bool isFinished;
    }

    mapping(uint => AgentRun) public agentRuns;
    uint private runCount;

    event AgentRunCreated(uint indexed runId, address indexed requester, InteractionType interactionType);
    event ResponseReceived(uint indexed runId, string response);

    constructor(address _oracleAddress, string memory _systemPrompt) {
        owner = msg.sender;
        oracleAddress = _oracleAddress;
        systemPrompt = _systemPrompt;
        
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

    function updateSystemPrompt(string memory _newPrompt) public onlyOwner {
        systemPrompt = _newPrompt;
    }

    function setOracleAddress(address _newOracleAddress) public onlyOwner {
        oracleAddress = _newOracleAddress;
    }

    function startAgentRun(string memory query, InteractionType interactionType, uint8 maxIterations) public returns (uint) {
        uint runId = runCount++;
        AgentRun storage run = agentRuns[runId];

        run.requester = msg.sender;
        run.interactionType = interactionType;
        run.maxIterations = maxIterations;
        run.currentIteration = 0;
        run.isFinished = false;

        IOracle.Content[] memory systemContent = new IOracle.Content[](1);
        systemContent[0] = IOracle.Content({contentType: "text", value: systemPrompt});
        run.messages.push(IOracle.Message({
            role: "system",
            content: systemContent
        }));

        IOracle.Content[] memory userContent = new IOracle.Content[](1);
        userContent[0] = IOracle.Content({contentType: "text", value: query});
        run.messages.push(IOracle.Message({
            role: "user",
            content: userContent
        }));

        IOracle(oracleAddress).createOpenAiLlmCall(runId, config);
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
            IOracle.Content[] memory errorContent = new IOracle.Content[](1);
            errorContent[0] = IOracle.Content({contentType: "text", value: errorMessage});
            run.messages.push(IOracle.Message({
                role: "assistant",
                content: errorContent
            }));
            run.isFinished = true;
            emit ResponseReceived(runId, errorMessage);
            return;
        }

        IOracle.Content[] memory responseContent = new IOracle.Content[](1);
        responseContent[0] = IOracle.Content({contentType: "text", value: response.content});
        run.messages.push(IOracle.Message({
            role: "assistant",
            content: responseContent
        }));
        emit ResponseReceived(runId, response.content);

        run.currentIteration++;

        if (run.currentIteration >= run.maxIterations || 
            run.interactionType == InteractionType.SingleResponse) {
            run.isFinished = true;
        } else if (run.interactionType == InteractionType.ChainOfThought || 
                   run.interactionType == InteractionType.Collaborative) {
            string memory nextPrompt = run.interactionType == InteractionType.ChainOfThought ?
                "Continue your chain of thought." :
                "Await human input for collaboration.";
            
            IOracle.Content[] memory nextPromptContent = new IOracle.Content[](1);
            nextPromptContent[0] = IOracle.Content({contentType: "text", value: nextPrompt});
            run.messages.push(IOracle.Message({
                role: "user",
                content: nextPromptContent
            }));

            IOracle(oracleAddress).createOpenAiLlmCall(runId, config);
        }
    }

    function addUserMessage(uint runId, string memory message) public {
        AgentRun storage run = agentRuns[runId];
        require(msg.sender == run.requester, "Only the run requester can add messages");
        require(!run.isFinished, "This run has finished");

        IOracle.Content[] memory userContent = new IOracle.Content[](1);
        userContent[0] = IOracle.Content({contentType: "text", value: message});
        run.messages.push(IOracle.Message({
            role: "user",
            content: userContent
        }));

        IOracle(oracleAddress).createOpenAiLlmCall(runId, config);
    }

    function getAgentRunMessages(uint runId) public view returns (IOracle.Message[] memory) {
        return agentRuns[runId].messages;
    }

    function isRunFinished(uint runId) public view returns (bool) {
        return agentRuns[runId].isFinished;
    }
}