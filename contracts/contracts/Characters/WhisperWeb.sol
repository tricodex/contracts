// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./interfaces/IOracle.sol";

contract WhisperWeb {
    address public oracleAddress;
    IOracle.OpenAiRequest private config;
    uint private intelCount;
    
    mapping(uint => IntelGathering) public intelOperations;
    
    struct IntelGathering {
        address owner;
        IOracle.Message[] messages;
        uint responsesCount;
        bool isFinished;
    }
    
    event IntelOperationStarted(address indexed owner, uint indexed operationId);

    constructor(address _oracleAddress) {
        oracleAddress = _oracleAddress;
        config = IOracle.OpenAiRequest({
            model: "gpt-4o",
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

    function startIntelOperation(string memory target) public returns (uint) {
        uint operationId = intelCount++;
        IntelGathering storage operation = intelOperations[operationId];
        
        operation.owner = msg.sender;
        operation.isFinished = false;
        operation.responsesCount = 0;
        
        string memory systemPrompt = "You are Whisper Web, a dark web informant. Gather intelligence on the given target without compromising ethics or legality.";
        operation.messages.push(createMessage("system", systemPrompt));
        operation.messages.push(createMessage("user", target));
        
        IOracle(oracleAddress).createOpenAiLlmCall(operationId, config);
        emit IntelOperationStarted(msg.sender, operationId);
        
        return operationId;
    }

    function onOracleOpenAiLlmResponse(
        uint operationId,
        IOracle.OpenAiResponse memory response,
        string memory errorMessage
    ) public {
        require(msg.sender == oracleAddress, "Unauthorized");
        IntelGathering storage operation = intelOperations[operationId];
        
        if (bytes(errorMessage).length > 0) {
            operation.messages.push(createMessage("assistant", errorMessage));
            operation.isFinished = true;
            return;
        }
        
        if (bytes(response.content).length > 0) {
            operation.messages.push(createMessage("assistant", response.content));
            operation.responsesCount++;
        }
        
        if (bytes(response.functionName).length > 0) {
            IOracle(oracleAddress).createFunctionCall(operationId, response.functionName, response.functionArguments);
        } else {
            operation.isFinished = true;
        }
    }

    function onOracleFunctionResponse(
        uint operationId,
        string memory response,
        string memory errorMessage
    ) public {
        require(msg.sender == oracleAddress, "Unauthorized");
        IntelGathering storage operation = intelOperations[operationId];
        require(!operation.isFinished, "Operation completed");

        string memory result = bytes(errorMessage).length > 0 ? errorMessage : response;
        operation.messages.push(createMessage("user", result));
        operation.responsesCount++;
        IOracle(oracleAddress).createOpenAiLlmCall(operationId, config);
    }

    function addUserInput(uint operationId, string memory input) public {
        IntelGathering storage operation = intelOperations[operationId];
        require(msg.sender == operation.owner, "Unauthorized");
        require(!operation.isFinished, "Operation completed");

        operation.messages.push(createMessage("user", input));
        IOracle(oracleAddress).createOpenAiLlmCall(operationId, config);
    }

    function createMessage(string memory role, string memory content) private pure returns (IOracle.Message memory) {
        IOracle.Message memory newMessage;
        newMessage.role = role;
        newMessage.content = new IOracle.Content[](1);
        newMessage.content[0].contentType = "text";
        newMessage.content[0].value = content;
        return newMessage;
    }

    function getOperationHistory(uint operationId) public view returns (IOracle.Message[] memory) {
        return intelOperations[operationId].messages;
    }

    function isOperationFinished(uint operationId) public view returns (bool) {
        return intelOperations[operationId].isFinished;
    }
}