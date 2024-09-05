// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./interfaces/IOracle.sol";

contract MetaverseProjectEvaluator {
    string public prompt;
    address private owner;
    address public oracleAddress;
    IOracle.OpenAiRequest private config;

    struct AgentRun {
        address owner;
        IOracle.Message[] messages;
        uint responsesCount;
        uint8 max_iterations;
        bool is_finished;
    }

    mapping(uint => AgentRun) public agentRuns;
    uint private agentRunCount;

    event AgentRunCreated(address indexed owner, uint indexed runId);
    event OracleAddressUpdated(address indexed newOracleAddress);

    constructor(address initialOracleAddress) {
        owner = msg.sender;
        oracleAddress = initialOracleAddress;
        prompt = "You are a Metaverse Project Evaluator, specializing in assessing virtual world projects, NFT-based ecosystems, and blockchain gaming initiatives. Provide comprehensive evaluations of metaverse projects, considering technical feasibility, market potential, and user engagement strategies.";
        _initializeConfig();
    }

    function _initializeConfig() private {
        config = IOracle.OpenAiRequest({
            model : "gpt-4o-2024-08-06",
            frequencyPenalty : 21,
            logitBias : "",
            maxTokens : 1000,
            presencePenalty : 21,
            responseFormat : "{\"type\":\"json_object\"}",
            seed : 0,
            stop : "",
            temperature : 10,
            topP : 101,
            tools : "[]",
            toolChoice : "auto",
            user : ""
        });
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not owner");
        _;
    }

    modifier onlyOracle() {
        require(msg.sender == oracleAddress, "Caller is not oracle");
        _;
    }

    function setOracleAddress(address newOracleAddress) public onlyOwner {
        oracleAddress = newOracleAddress;
        emit OracleAddressUpdated(newOracleAddress);
    }

    function runAgent(string memory query, uint8 max_iterations) public returns (uint) {
        AgentRun storage run = agentRuns[agentRunCount];
        run.owner = msg.sender;
        run.is_finished = false;
        run.responsesCount = 0;
        run.max_iterations = max_iterations;

        run.messages.push(createTextMessage("system", prompt));
        run.messages.push(createTextMessage("user", query));

        uint currentId = agentRunCount++;
        IOracle(oracleAddress).createOpenAiLlmCall(currentId, config);
        emit AgentRunCreated(run.owner, currentId);
        return currentId;
    }

    function onOracleOpenAiLlmResponse(
        uint runId,
        IOracle.OpenAiResponse memory response,
        string memory errorMessage
    ) public onlyOracle {
        AgentRun storage run = agentRuns[runId];

        if (bytes(errorMessage).length > 0) {
            run.messages.push(createTextMessage("assistant", errorMessage));
            run.is_finished = true;
        } else if (run.responsesCount >= run.max_iterations) {
            run.is_finished = true;
        } else if (bytes(response.content).length > 0) {
            run.messages.push(createTextMessage("assistant", response.content));
            run.responsesCount++;
        }

        if (!run.is_finished) {
            IOracle(oracleAddress).createOpenAiLlmCall(runId, config);
        }
    }

    function getMessageHistory(uint agentId) public view returns (IOracle.Message[] memory) {
        return agentRuns[agentId].messages;
    }

    function isRunFinished(uint runId) public view returns (bool) {
        return agentRuns[runId].is_finished;
    }

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