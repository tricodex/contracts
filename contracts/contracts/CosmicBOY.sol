// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./interfaces/IOracle.sol";

contract GaladrielCosmicAgentNetwork {
    address public owner;
    address public oracleAddress;

    struct Agent {
        IOracle.Message[] messages;
        uint256 stepCount;
        bool isActive;
        string knowledgeBaseCID;
        uint8 maxIterations;
        string role;
        uint256[] collaborators;
        mapping(string => string) memory;
        string[] skills;
        uint256 experiencePoints;
        uint256 level;
        string[] multimodalCapabilities;
    }

    struct Swarm {
        uint256[] agentIds;
        string objective;
        bool isActive;
        mapping(string => string) sharedMemory;
        uint256 leadAgentId;
        string emergentBehavior;
        uint256 collectiveIntelligence;
    }

    mapping(uint256 => Agent) public agents;
    mapping(uint256 => Swarm) public swarms;
    uint256 public nextAgentId;
    uint256 public nextSwarmId;

    string public globalKnowledgeBaseCID;
    
    IOracle.OpenAiRequest private config;

    event AgentCreated(uint256 agentId, string role);
    event AgentResponse(uint256 agentId, string response);
    event SwarmCreated(uint256 swarmId, string objective);
    event KnowledgeBaseUpdated(uint256 agentId, string newCID);
    event GlobalKnowledgeBaseUpdated(string newCID);
    event MultimodalInteractionProcessed(uint256 agentId, string[] modalitiesUsed);

    constructor(address _oracleAddress) {
        owner = msg.sender;
        oracleAddress = _oracleAddress;

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
            tools: "[{\"type\":\"function\",\"function\":{\"name\":\"web_search\",\"description\":\"Search the internet\",\"parameters\":{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"Search query\"}},\"required\":[\"query\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"image_generation\",\"description\":\"Generates an image using Dalle-2\",\"parameters\":{\"type\":\"object\",\"properties\":{\"prompt\":{\"type\":\"string\",\"description\":\"Dalle-2 prompt to generate an image\"}},\"required\":[\"prompt\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"knowledge_base_query\",\"description\":\"Query the knowledge base\",\"parameters\":{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"Query for the knowledge base\"},\"num_documents\":{\"type\":\"integer\",\"description\":\"Number of documents to retrieve\"}},\"required\":[\"query\",\"num_documents\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"update_knowledge_base\",\"description\":\"Update the agent's knowledge base\",\"parameters\":{\"type\":\"object\",\"properties\":{\"newCID\":{\"type\":\"string\",\"description\":\"New IPFS CID for the updated knowledge base\"}},\"required\":[\"newCID\"]}}}]",
            toolChoice: "auto",
            user: ""
        });
    }

    function createAgent(
        string memory systemPrompt,
        string memory knowledgeBaseCID,
        uint8 maxIterations,
        string memory role,
        string[] memory initialSkills
    ) external returns (uint256) {
        uint256 agentId = nextAgentId++;
        Agent storage newAgent = agents[agentId];
        newAgent.stepCount = 0;
        newAgent.isActive = true;
        newAgent.knowledgeBaseCID = knowledgeBaseCID;
        newAgent.maxIterations = maxIterations;
        newAgent.role = role;
        newAgent.skills = initialSkills;
        newAgent.experiencePoints = 0;
        newAgent.level = 1;
        newAgent.multimodalCapabilities = ["text", "image"];

        IOracle.Message memory systemMessage = IOracle.Message({
            role: "system",
            content: new IOracle.Content[](1)
        });
        systemMessage.content[0] = IOracle.Content({
            contentType: "text",
            value: systemPrompt
        });
        newAgent.messages.push(systemMessage);

        emit AgentCreated(agentId, role);
        return agentId;
    }

    function createSwarm(
        uint256[] memory agentIds,
        string memory objective,
        uint256 leadAgentId
    ) external returns (uint256) {
        uint256 swarmId = nextSwarmId++;
        Swarm storage newSwarm = swarms[swarmId];
        newSwarm.agentIds = agentIds;
        newSwarm.objective = objective;
        newSwarm.isActive = true;
        newSwarm.leadAgentId = leadAgentId;

        emit SwarmCreated(swarmId, objective);
        return swarmId;
    }

    function processMultimodalInteraction(
        uint256 agentId,
        string[] memory modalityTypes,
        string[] memory modalityContents
    ) external {
        require(agents[agentId].isActive, "Agent is not active");
        require(modalityTypes.length == modalityContents.length, "Modality types and contents mismatch");

        IOracle.Message memory multimodalMessage = IOracle.Message({
            role: "user",
            content: new IOracle.Content[](modalityTypes.length)
        });

        for (uint i = 0; i < modalityTypes.length; i++) {
            multimodalMessage.content[i] = IOracle.Content({
                contentType: modalityTypes[i],
                value: modalityContents[i]
            });
        }

        agents[agentId].messages.push(multimodalMessage);
        agents[agentId].stepCount++;

        IOracle(oracleAddress).createOpenAiLlmCall(agentId, config);

        emit MultimodalInteractionProcessed(agentId, modalityTypes);
    }

    function performRAG(uint256 agentId, string memory query) external {
        require(agents[agentId].isActive, "Agent is not active");
        string memory knowledgeBaseCID = agents[agentId].knowledgeBaseCID;
        
        IOracle(oracleAddress).createKnowledgeBaseQuery(agentId, knowledgeBaseCID, query, 3);
    }

    function onOracleKnowledgeBaseQueryResponse(
        uint256 agentId,
        string[] memory documents,
        string memory errorMessage
    ) external {
        require(msg.sender == oracleAddress, "Only oracle can call this function");
        
        string memory contextMessage = "";
        for (uint i = 0; i < documents.length; i++) {
            contextMessage = string(abi.encodePacked(contextMessage, documents[i], "\n"));
        }
        
        IOracle.Message memory contextMsg = IOracle.Message({
            role: "system",
            content: new IOracle.Content[](1)
        });
        contextMsg.content[0] = IOracle.Content({
            contentType: "text",
            value: string(abi.encodePacked("Relevant context:\n", contextMessage))
        });
        agents[agentId].messages.push(contextMsg);
        
        IOracle(oracleAddress).createOpenAiLlmCall(agentId, config);
    }

    function onOracleOpenAiLlmResponse(
        uint256 agentId,
        IOracle.OpenAiResponse memory response,
        string memory errorMessage
    ) external {
        require(msg.sender == oracleAddress, "Only oracle can call this function");
        
        Agent storage agent = agents[agentId];
        
        if (bytes(errorMessage).length > 0) {
            emit AgentResponse(agentId, errorMessage);
            return;
        }

        if (bytes(response.content).length > 0) {
            IOracle.Message memory assistantMessage = IOracle.Message({
                role: "assistant",
                content: new IOracle.Content[](1)
            });
            assistantMessage.content[0] = IOracle.Content({
                contentType: "text",
                value: response.content
            });
            agent.messages.push(assistantMessage);
            emit AgentResponse(agentId, response.content);
        }

        if (bytes(response.functionName).length > 0) {
            executeLlmFunction(agentId, response.functionName, response.functionArguments);
        }

        agent.experiencePoints += 10;
        if (agent.experiencePoints >= 100 * agent.level) {
            evolveAgent(agentId);
        }
    }

    function executeLlmFunction(uint256 agentId, string memory functionName, string memory functionArguments) internal {
        if (keccak256(abi.encodePacked(functionName)) == keccak256(abi.encodePacked("web_search"))) {
            IOracle(oracleAddress).createFunctionCall(agentId, "web_search", functionArguments);
        } else if (keccak256(abi.encodePacked(functionName)) == keccak256(abi.encodePacked("image_generation"))) {
            IOracle(oracleAddress).createFunctionCall(agentId, "image_generation", functionArguments);
        } else if (keccak256(abi.encodePacked(functionName)) == keccak256(abi.encodePacked("knowledge_base_query"))) {
            (string memory query, uint256 num_documents) = abi.decode(bytes(functionArguments), (string, uint256));
            IOracle(oracleAddress).createKnowledgeBaseQuery(agentId, agents[agentId].knowledgeBaseCID, query, uint32(num_documents));
        } else if (keccak256(abi.encodePacked(functionName)) == keccak256(abi.encodePacked("update_knowledge_base"))) {
            (string memory newCID) = abi.decode(bytes(functionArguments), (string));
            updateAgentKnowledgeBase(agentId, newCID);
        }
    }

    function onOracleFunctionResponse(
        uint256 agentId,
        string memory functionName,
        string memory response,
        string memory errorMessage
    ) external {
        require(msg.sender == oracleAddress, "Only oracle can call this function");

        IOracle.Message memory functionResponseMsg = IOracle.Message({
            role: "function",
            content: new IOracle.Content[](1)
        });
        functionResponseMsg.content[0] = IOracle.Content({
            contentType: "text",
            value: response
        });
        agents[agentId].messages.push(functionResponseMsg);

        IOracle(oracleAddress).createOpenAiLlmCall(agentId, config);
    }

    function evolveAgent(uint256 agentId) internal {
        Agent storage agent = agents[agentId];
        agent.level++;
        agent.maxIterations++;
        
        if (agent.level % 5 == 0) {
            agent.multimodalCapabilities.push("advanced_reasoning");
        }

        emit AgentEvolved(agentId, agent.level);
    }

    function updateAgentKnowledgeBase(uint256 agentId, string memory newCID) internal {
        agents[agentId].knowledgeBaseCID = newCID;
        emit KnowledgeBaseUpdated(agentId, newCID);
    }

    function updateGlobalKnowledgeBase(string memory newCID) external {
        require(msg.sender == owner, "Only owner can update global knowledge base");
        globalKnowledgeBaseCID = newCID;
        emit GlobalKnowledgeBaseUpdated(newCID);
    }

    function initiateSwarmCollaboration(uint256 swarmId, string memory task) external {
        Swarm storage swarm = swarms[swarmId];
        require(swarm.isActive, "Swarm is not active");

        for (uint i = 0; i < swarm.agentIds.length; i++) {
            uint256 agentId = swarm.agentIds[i];
            IOracle.Message memory collaborationMsg = IOracle.Message({
                role: "system",
                content: new IOracle.Content[](1)
            });
            collaborationMsg.content[0] = IOracle.Content({
                contentType: "text",
                value: string(abi.encodePacked("Collaborate on task: ", task))
            });
            agents[agentId].messages.push(collaborationMsg);
            IOracle(oracleAddress).createOpenAiLlmCall(agentId, config);
        }

        emit SwarmCollaborationInitiated(swarmId, task);
    }

    function synthesizeSwarmKnowledge(uint256 swarmId) external {
        Swarm storage swarm = swarms[swarmId];
        require(swarm.isActive, "Swarm is not active");

        string memory combinedKnowledge = "";
        for (uint i = 0; i < swarm.agentIds.length; i++) {
            combinedKnowledge = string(abi.encodePacked(combinedKnowledge, agents[swarm.agentIds[i]].knowledgeBaseCID, "\n"));
        }

        IOracle.Message memory synthesisMsg = IOracle.Message({
            role: "system",
            content: new IOracle.Content[](1)
        });
        synthesisMsg.content[0] = IOracle.Content({
            contentType: "text",
            value: string(abi.encodePacked("Synthesize the following knowledge bases:\n", combinedKnowledge))
        });

        uint256 synthesisAgentId = nextAgentId++;
        agents[synthesisAgentId].isActive = true;
        agents[synthesisAgentId].messages.push(synthesisMsg);

        IOracle(oracleAddress).createOpenAiLlmCall(synthesisAgentId, config);

        emit SwarmKnowledgeSynthesisInitiated(swarmId, synthesisAgentId);
    }

    event AgentEvolved(uint256 agentId, uint256 newLevel);
    event SwarmCollaborationInitiated(uint256 swarmId, string task);
    event SwarmKnowledgeSynthesisInitiated(uint256 swarmId, uint256 synthesisAgentId);
}