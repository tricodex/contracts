// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./interfaces/IOracle.sol";

contract CryptKeeper {
    address public oracleAddress;
    IOracle.OpenAiRequest private config;
    uint private auditCount;
    
    mapping(uint => Audit) public audits;
    
    struct Audit {
        address owner;
        IOracle.Message[] messages;
        uint responsesCount;
        bool isFinished;
    }
    
    event AuditStarted(address indexed owner, uint indexed auditId);

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

    function startAudit(string memory contractCode) public returns (uint) {
        uint auditId = auditCount++;
        Audit storage audit = audits[auditId];
        
        audit.owner = msg.sender;
        audit.isFinished = false;
        audit.responsesCount = 0;
        
        string memory systemPrompt = "You are Crypt Keeper, a blockchain security expert. Analyze the given smart contract code for vulnerabilities and security issues.";
        audit.messages.push(createMessage("system", systemPrompt));
        audit.messages.push(createMessage("user", contractCode));
        
        IOracle(oracleAddress).createOpenAiLlmCall(auditId, config);
        emit AuditStarted(msg.sender, auditId);
        
        return auditId;
    }

    function onOracleOpenAiLlmResponse(
        uint auditId,
        IOracle.OpenAiResponse memory response,
        string memory errorMessage
    ) public {
        require(msg.sender == oracleAddress, "Unauthorized");
        Audit storage audit = audits[auditId];
        
        if (bytes(errorMessage).length > 0) {
            audit.messages.push(createMessage("assistant", errorMessage));
            audit.isFinished = true;
            return;
        }
        
        if (bytes(response.content).length > 0) {
            audit.messages.push(createMessage("assistant", response.content));
            audit.responsesCount++;
        }
        
        if (bytes(response.functionName).length > 0) {
            IOracle(oracleAddress).createFunctionCall(auditId, response.functionName, response.functionArguments);
        } else {
            audit.isFinished = true;
        }
    }

    function onOracleFunctionResponse(
        uint auditId,
        string memory response,
        string memory errorMessage
    ) public {
        require(msg.sender == oracleAddress, "Unauthorized");
        Audit storage audit = audits[auditId];
        require(!audit.isFinished, "Audit completed");

        string memory result = bytes(errorMessage).length > 0 ? errorMessage : response;
        audit.messages.push(createMessage("user", result));
        audit.responsesCount++;
        IOracle(oracleAddress).createOpenAiLlmCall(auditId, config);
    }

    function addUserInput(uint auditId, string memory input) public {
        Audit storage audit = audits[auditId];
        require(msg.sender == audit.owner, "Unauthorized");
        require(!audit.isFinished, "Audit completed");

        audit.messages.push(createMessage("user", input));
        IOracle(oracleAddress).createOpenAiLlmCall(auditId, config);
    }

    function createMessage(string memory role, string memory content) private pure returns (IOracle.Message memory) {
        IOracle.Message memory newMessage;
        newMessage.role = role;
        newMessage.content = new IOracle.Content[](1);
        newMessage.content[0].contentType = "text";
        newMessage.content[0].value = content;
        return newMessage;
    }

    function getAuditHistory(uint auditId) public view returns (IOracle.Message[] memory) {
        return audits[auditId].messages;
    }

    function isAuditFinished(uint auditId) public view returns (bool) {
        return audits[auditId].isFinished;
    }
}