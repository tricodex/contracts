// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./interfaces/IOracle.sol";

contract BlockchainBloodhound {
    address public oracleAddress;
    IOracle.OpenAiRequest private config;
    uint private traceCount;
    
    mapping(uint => Trace) public traces;
    
    struct Trace {
        address owner;
        IOracle.Message[] messages;
        uint responsesCount;
        bool isFinished;
    }
    
    event TraceStarted(address indexed owner, uint indexed traceId);

    constructor(address _oracleAddress) {
        oracleAddress = _oracleAddress;
        config = IOracle.OpenAiRequest({
            model: "gpt-4o-2024-08-06",
            frequencyPenalty: 21,
            logitBias: "",
            maxTokens: 1000,
            presencePenalty: 21,
            responseFormat: '{"type":"text"}',
            seed: 0,
            stop: "",
            temperature: 10,
            topP: 101,
            tools: "[{\"type\":\"function\",\"function\":{\"name\":\"web_search\",\"description\":\"Search the internet\",\"parameters\":{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"Search query\"}},\"required\":[\"query\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"image_generation\",\"description\":\"Generates an image using Dalle-2\",\"parameters\":{\"type\":\"object\",\"properties\":{\"prompt\":{\"type\":\"string\",\"description\":\"Dalle-2 prompt to generate an image\"}},\"required\":[\"prompt\"]}}}]",
            toolChoice: "auto",
            user: ""
        });
    }

    function startTrace(string memory transactionHash) public returns (uint) {
        uint traceId = traceCount++;
        Trace storage trace = traces[traceId];
        
        trace.owner = msg.sender;
        trace.isFinished = false;
        trace.responsesCount = 0;
        
        string memory systemPrompt = "You are Blockchain Bloodhound, an expert in tracing cryptocurrency transactions. Analyze the given transaction and provide insights.";
        trace.messages.push(createMessage("system", systemPrompt));
        trace.messages.push(createMessage("user", transactionHash));
        
        IOracle(oracleAddress).createOpenAiLlmCall(traceId, config);
        emit TraceStarted(msg.sender, traceId);
        
        return traceId;
    }

    function onOracleOpenAiLlmResponse(
        uint traceId,
        IOracle.OpenAiResponse memory response,
        string memory errorMessage
    ) public {
        require(msg.sender == oracleAddress, "Unauthorized");
        Trace storage trace = traces[traceId];
        
        if (bytes(errorMessage).length > 0) {
            trace.messages.push(createMessage("assistant", errorMessage));
            trace.isFinished = true;
            return;
        }
        
        if (bytes(response.content).length > 0) {
            trace.messages.push(createMessage("assistant", response.content));
            trace.responsesCount++;
        }
        
        if (bytes(response.functionName).length > 0) {
            IOracle(oracleAddress).createFunctionCall(traceId, response.functionName, response.functionArguments);
        } else {
            trace.isFinished = true;
        }
    }

    function onOracleFunctionResponse(
        uint traceId,
        string memory response,
        string memory errorMessage
    ) public {
        require(msg.sender == oracleAddress, "Unauthorized");
        Trace storage trace = traces[traceId];
        require(!trace.isFinished, "Trace completed");

        string memory result = bytes(errorMessage).length > 0 ? errorMessage : response;
        trace.messages.push(createMessage("user", result));
        trace.responsesCount++;
        IOracle(oracleAddress).createOpenAiLlmCall(traceId, config);
    }

    function addUserInput(uint traceId, string memory input) public {
        Trace storage trace = traces[traceId];
        require(msg.sender == trace.owner, "Unauthorized");
        require(!trace.isFinished, "Trace completed");

        trace.messages.push(createMessage("user", input));
        IOracle(oracleAddress).createOpenAiLlmCall(traceId, config);
    }

    function createMessage(string memory role, string memory content) private pure returns (IOracle.Message memory) {
        IOracle.Message memory newMessage;
        newMessage.role = role;
        newMessage.content = new IOracle.Content[](1);
        newMessage.content[0].contentType = "text";
        newMessage.content[0].value = content;
        return newMessage;
    }

    function getTraceHistory(uint traceId) public view returns (IOracle.Message[] memory) {
        return traces[traceId].messages;
    }

    function isTraceFinished(uint traceId) public view returns (bool) {
        return traces[traceId].isFinished;
    }
}