// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./interfaces/IOracle.sol";

contract DAOArchitect {
    address public oracleAddress;
    IOracle.OpenAiRequest private config;
    uint private projectCount;
    
    struct DAOProject {
        address owner;
        IOracle.Message[] messages;
        uint stage;
        bool isFinished;
        string governanceStructure;
        string tokenomics;
        string smartContracts;
        string frontendDesign;
        string legalCompliance;
    }
    
    mapping(uint => DAOProject) public projects;
    
    event ProjectStarted(address indexed owner, uint indexed projectId);
    event StageCompleted(uint indexed projectId, uint stage);

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
            tools: "[{\"type\":\"function\",\"function\":{\"name\":\"consultGovernanceExpert\",\"description\":\"Consult the Governance Expert agent\",\"parameters\":{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"Governance-related query\"}},\"required\":[\"query\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"consultTokenomicsWizard\",\"description\":\"Consult the Tokenomics Wizard agent\",\"parameters\":{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"Tokenomics-related query\"}},\"required\":[\"query\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"consultSmartContractForge\",\"description\":\"Consult the Smart Contract Forge agent\",\"parameters\":{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"Smart contract-related query\"}},\"required\":[\"query\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"consultUXAlchemist\",\"description\":\"Consult the UX Alchemist agent\",\"parameters\":{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"Frontend design-related query\"}},\"required\":[\"query\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"consultLegalSage\",\"description\":\"Consult the Legal Sage agent\",\"parameters\":{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"Legal compliance-related query\"}},\"required\":[\"query\"]}}]",
            toolChoice: "auto",
            user: ""
        });
    }

    function startDAOProject(string memory projectDescription) public returns (uint) {
        uint projectId = projectCount++;
        DAOProject storage project = projects[projectId];
        
        project.owner = msg.sender;
        project.stage = 0;
        project.isFinished = false;
        
        string memory systemPrompt = "You are the DAOArchitect, orchestrating the creation of a Decentralized Autonomous Organization. Guide the process through all stages, consulting specialized agents when needed.";
        project.messages.push(createMessage("system", systemPrompt));
        project.messages.push(createMessage("user", projectDescription));
        
        IOracle(oracleAddress).createOpenAiLlmCall(projectId, config);
        emit ProjectStarted(msg.sender, projectId);
        
        return projectId;
    }

    function onOracleOpenAiLlmResponse(
        uint projectId,
        IOracle.OpenAiResponse memory response,
        string memory errorMessage
    ) public {
        require(msg.sender == oracleAddress, "Unauthorized");
        DAOProject storage project = projects[projectId];
        
        if (bytes(errorMessage).length > 0) {
            project.messages.push(createMessage("assistant", errorMessage));
            return;
        }
        
        if (bytes(response.content).length > 0) {
            project.messages.push(createMessage("assistant", response.content));
            advanceStage(projectId);
        }
        
        if (bytes(response.functionName).length > 0) {
            IOracle(oracleAddress).createFunctionCall(projectId, response.functionName, response.functionArguments);
        }
    }

    function onOracleFunctionResponse(
        uint projectId,
        string memory response,
        string memory errorMessage
    ) public {
        require(msg.sender == oracleAddress, "Unauthorized");
        DAOProject storage project = projects[projectId];
        
        string memory result = bytes(errorMessage).length > 0 ? errorMessage : response;
        project.messages.push(createMessage("user", result));
        
        if (project.stage == 1) project.governanceStructure = result;
        else if (project.stage == 2) project.tokenomics = result;
        else if (project.stage == 3) project.smartContracts = result;
        else if (project.stage == 4) project.frontendDesign = result;
        else if (project.stage == 5) project.legalCompliance = result;
        
        IOracle(oracleAddress).createOpenAiLlmCall(projectId, config);
    }

    function addUserInput(uint projectId, string memory input) public {
        DAOProject storage project = projects[projectId];
        require(msg.sender == project.owner, "Unauthorized");
        require(!project.isFinished, "Project completed");

        project.messages.push(createMessage("user", input));
        IOracle(oracleAddress).createOpenAiLlmCall(projectId, config);
    }

    function advanceStage(uint projectId) private {
        DAOProject storage project = projects[projectId];
        project.stage++;
        emit StageCompleted(projectId, project.stage);
        
        if (project.stage >= 5) {
            project.isFinished = true;
        }
    }

    function createMessage(string memory role, string memory content) private pure returns (IOracle.Message memory) {
        IOracle.Message memory newMessage;
        newMessage.role = role;
        newMessage.content = new IOracle.Content[](1);
        newMessage.content[0].contentType = "text";
        newMessage.content[0].value = content;
        return newMessage;
    }

    function getProjectHistory(uint projectId) public view returns (IOracle.Message[] memory) {
        return projects[projectId].messages;
    }

    function getProjectStatus(uint projectId) public view returns (uint stage, bool isFinished) {
        DAOProject storage project = projects[projectId];
        return (project.stage, project.isFinished);
    }
}