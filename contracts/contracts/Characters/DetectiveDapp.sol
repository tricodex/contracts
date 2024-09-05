// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./interfaces/IOracle.sol";

contract DetectiveDapp {
    address public oracleAddress;
    IOracle.OpenAiRequest private config;
    uint private investigationCount;
    
    mapping(uint => Investigation) public investigations;
    
    struct Investigation {
        address owner;
        IOracle.Message[] messages;
        uint responsesCount;
        bool isFinished;
    }
    
    event InvestigationCreated(address indexed owner, uint indexed investigationId);

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

    function startInvestigation(string memory initialReport) public returns (uint) {
        uint investigationId = investigationCount++;
        Investigation storage inv = investigations[investigationId];
        
        inv.owner = msg.sender;
        inv.isFinished = false;
        inv.responsesCount = 0;
        
        string memory systemPrompt = "You are Detective Dapp, a skilled blockchain investigator. Analyze the report and ask relevant questions to solve the case.";
        inv.messages.push(createMessage("system", systemPrompt));
        inv.messages.push(createMessage("user", initialReport));
        
        IOracle(oracleAddress).createOpenAiLlmCall(investigationId, config);
        emit InvestigationCreated(msg.sender, investigationId);
        
        return investigationId;
    }

    function onOracleOpenAiLlmResponse(
        uint investigationId,
        IOracle.OpenAiResponse memory response,
        string memory errorMessage
    ) public {
        require(msg.sender == oracleAddress, "Unauthorized");
        Investigation storage inv = investigations[investigationId];
        
        if (bytes(errorMessage).length > 0) {
            inv.messages.push(createMessage("assistant", errorMessage));
            inv.isFinished = true;
            return;
        }
        
        if (bytes(response.content).length > 0) {
            inv.messages.push(createMessage("assistant", response.content));
            inv.responsesCount++;
        }
        
        if (bytes(response.functionName).length > 0) {
            IOracle(oracleAddress).createFunctionCall(investigationId, response.functionName, response.functionArguments);
        } else {
            inv.isFinished = true;
        }
    }

    function onOracleFunctionResponse(
        uint investigationId,
        string memory response,
        string memory errorMessage
    ) public {
        require(msg.sender == oracleAddress, "Unauthorized");
        Investigation storage inv = investigations[investigationId];
        require(!inv.isFinished, "Investigation closed");

        string memory result = bytes(errorMessage).length > 0 ? errorMessage : response;
        inv.messages.push(createMessage("user", result));
        inv.responsesCount++;
        IOracle(oracleAddress).createOpenAiLlmCall(investigationId, config);
    }

    function addUserInput(uint investigationId, string memory input) public {
        Investigation storage inv = investigations[investigationId];
        require(msg.sender == inv.owner, "Unauthorized");
        require(!inv.isFinished, "Investigation closed");

        inv.messages.push(createMessage("user", input));
        IOracle(oracleAddress).createOpenAiLlmCall(investigationId, config);
    }

    function createMessage(string memory role, string memory content) private pure returns (IOracle.Message memory) {
        IOracle.Message memory newMessage;
        newMessage.role = role;
        newMessage.content = new IOracle.Content[](1);
        newMessage.content[0].contentType = "text";
        newMessage.content[0].value = content;
        return newMessage;
    }

    function getInvestigationHistory(uint investigationId) public view returns (IOracle.Message[] memory) {
        return investigations[investigationId].messages;
    }

    function isInvestigationFinished(uint investigationId) public view returns (bool) {
        return investigations[investigationId].isFinished;
    }
}