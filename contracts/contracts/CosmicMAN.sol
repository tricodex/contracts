// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./interfaces/IOracle.sol";

contract CosmicMultiAgentNetwork {
    
    // Contract variables
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
        mapping(string => string) memory; // Personal memory mapping
        string[] skills;
        uint256 experiencePoints;
        uint256 level;
        string[] traits;
        mapping(string => uint256) attributeScores; // Attribute scores mapping
        string[] specializations;
        uint256 autonomyLevel;
        string[] multimodalCapabilities;
    }
    
    struct Swarm {
        uint256[] agentIds;
        string objective;
        bool isActive;
        mapping(string => string) sharedMemory; // Shared memory mapping
        uint256 leadAgentId;
        SwarmState state;
        string emergentBehavior;
        uint256 collectiveIntelligence;
        string[] swarmTraits;
        uint256 swarmEvolutionStage;
        string[] swarmSpecializations;
    }
    
    enum SwarmState { 
        Forming, 
        Storming, 
        Norming, 
        Performing, 
        Adjourning, 
        Evolving, 
        Transcending, 
        Cosmic 
    }
    
    // Mappings to store agents and swarms
    mapping(uint256 => Agent) public agents;
    mapping(uint256 => Swarm) public swarms;
    
    // Variables for tracking the next ID for agents and swarms
    uint256 public nextAgentId;
    uint256 public nextSwarmId;
    
    // System-wide variables
    string public globalKnowledgeBaseCID;
    uint256 public systemEvolutionStage;
    string[] public systemCapabilities;
    
    // Oracle configuration
    IOracle.OpenAiRequest private config;
    
    // Events
    event AgentCreated(uint256 agentId, string role);
    event AgentResponse(uint256 agentId, string response);
    event AgentCollaboration(uint256 agentId, uint256 collaboratorId, string message);
    event SwarmCreated(uint256 swarmId, string objective);
    event SwarmStateChanged(uint256 swarmId, SwarmState newState);
    event SwarmCompleted(uint256 swarmId, string result);
    event KnowledgeBaseUpdated(uint256 agentId, string newCID);
    event GlobalKnowledgeBaseUpdated(string newCID);
    event AgentSkillAcquired(uint256 agentId, string newSkill);
    event AgentLeveledUp(uint256 agentId, uint256 newLevel);
    event EmergentBehaviorDetected(uint256 swarmId, string behavior);
    event AgentEvolved(uint256 agentId, string[] newTraits);
    event SwarmEvolved(uint256 swarmId, uint256 newEvolutionStage);
    event SystemEvolved(uint256 newEvolutionStage, string[] newCapabilities);
    event MultimodalInteractionProcessed(uint256 agentId, string[] modalitiesUsed);
    
    constructor(address _oracleAddress) {
        owner = msg.sender;
        oracleAddress = _oracleAddress;
        systemEvolutionStage = 1;
        systemCapabilities = ["text", "image"];
        
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
            tools: "[{\"type\":\"function\",\"function\":{\"name\":\"web_search\",\"description\":\"Search the internet\",\"parameters\":{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"Search query\"}},\"required\":[\"query\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"image_generation\",\"description\":\"Generates an image using Dalle-2\",\"parameters\":{\"type\":\"object\",\"properties\":{\"prompt\":{\"type\":\"string\",\"description\":\"Dalle-2 prompt to generate an image\"}},\"required\":[\"prompt\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"collaborate\",\"description\":\"Collaborate with another agent\",\"parameters\":{\"type\":\"object\",\"properties\":{\"agentId\":{\"type\":\"number\",\"description\":\"ID of the agent to collaborate with\"},\"message\":{\"type\":\"string\",\"description\":\"Message to send to the collaborator\"}},\"required\":[\"agentId\",\"message\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"update_memory\",\"description\":\"Update agent's personal memory\",\"parameters\":{\"type\":\"object\",\"properties\":{\"key\":{\"type\":\"string\",\"description\":\"Memory key\"},\"value\":{\"type\":\"string\",\"description\":\"Memory value\"}},\"required\":[\"key\",\"value\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"update_knowledge_base\",\"description\":\"Update the agent's knowledge base\",\"parameters\":{\"type\":\"object\",\"properties\":{\"newCID\":{\"type\":\"string\",\"description\":\"New IPFS CID for the updated knowledge base\"}},\"required\":[\"newCID\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"acquire_skill\",\"description\":\"Acquire a new skill\",\"parameters\":{\"type\":\"object\",\"properties\":{\"skill\":{\"type\":\"string\",\"description\":\"Name of the skill to acquire\"}},\"required\":[\"skill\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"update_swarm_memory\",\"description\":\"Update swarm's shared memory\",\"parameters\":{\"type\":\"object\",\"properties\":{\"swarmId\":{\"type\":\"number\",\"description\":\"ID of the swarm\"},\"key\":{\"type\":\"string\",\"description\":\"Memory key\"},\"value\":{\"type\":\"string\",\"description\":\"Memory value\"}},\"required\":[\"swarmId\",\"key\",\"value\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"change_swarm_state\",\"description\":\"Change the state of a swarm\",\"parameters\":{\"type\":\"object\",\"properties\":{\"swarmId\":{\"type\":\"number\",\"description\":\"ID of the swarm\"},\"newState\":{\"type\":\"string\",\"enum\":[\"Forming\",\"Storming\",\"Norming\",\"Performing\",\"Adjourning\",\"Evolving\",\"Transcending\",\"Cosmic\"],\"description\":\"New state of the swarm\"}},\"required\":[\"swarmId\",\"newState\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"autonomous_decision\",\"description\":\"Make an autonomous decision based on current context\",\"parameters\":{\"type\":\"object\",\"properties\":{\"context\":{\"type\":\"string\",\"description\":\"Current context for decision-making\"},\"options\":{\"type\":\"array\",\"items\":{\"type\":\"string\"},\"description\":\"List of possible decisions\"}},\"required\":[\"context\",\"options\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"synthesize_knowledge\",\"description\":\"Synthesize knowledge from multiple sources\",\"parameters\":{\"type\":\"object\",\"properties\":{\"sources\":{\"type\":\"array\",
        });
    }

    function updateGlobalKnowledgeBase(string memory newCID) external {
        globalKnowledgeBaseCID = newCID;
        emit GlobalKnowledgeBaseUpdated(newCID);
    }
    function createAgent(
        string memory systemPrompt,
        string memory knowledgeBaseCID,
        uint8 maxIterations,
        string memory role,
        string[] memory initialSkills,
        string[] memory initialTraits
    ) external returns (uint256) {
        uint256 agentId = nextAgentId++;
        Agent storage newAgent = agents[agentId];
        newAgent.stepCount = 0;
        newAgent.isActive = true;
        newAgent.knowledgeBaseCID = knowledgeBaseCID;
        newAgent.maxIterations = maxIterations;
        newAgent.role = role;
        newAgent.skills = initialSkills;
        newAgent.traits = initialTraits;
        newAgent.experiencePoints = 0;
        newAgent.level = 1;
        newAgent.autonomyLevel = 1;
        newAgent.multimodalCapabilities = systemCapabilities;

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
        newSwarm.state = SwarmState.Forming;
        newSwarm.swarmEvolutionStage = 1;

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

    function evolveAgent(uint256 agentId) internal {
        Agent storage agent = agents[agentId];
        require(agent.isActive, "Agent is not active");

        agent.level++;
        agent.autonomyLevel++;

        string[] memory evolvedTraits = new string[](agent.traits.length + 1);
        for (uint i = 0; i < agent.traits.length; i++) {
            evolvedTraits[i] = agent.traits[i];
        }
        evolvedTraits[agent.traits.length] = "Evolved";
        agent.traits = evolvedTraits;

        emit AgentEvolved(agentId, agent.traits);
    }

    function evolveSwarm(uint256 swarmId) internal {
        Swarm storage swarm = swarms[swarmId];
        require(swarm.isActive, "Swarm is not active");

        swarm.swarmEvolutionStage++;
        if (swarm.swarmEvolutionStage >= 5) {
            swarm.state = SwarmState.Cosmic;
        } else {
            swarm.state = SwarmState.Evolving;
        }

        emit SwarmEvolved(swarmId, swarm.swarmEvolutionStage);
    }

    function synthesizeKnowledge(uint256 agentId, string[] memory sources) external {
        require(agents[agentId].isActive, "Agent is not active");

        string memory synthesizedKnowledge = "Synthesized knowledge from multiple sources";
        agents[agentId].knowledgeBaseCID = synthesizedKnowledge;

        emit KnowledgeBaseUpdated(agentId, synthesizedKnowledge);
    }

    function detectEmergentBehavior(uint256 swarmId) external {
        Swarm storage swarm = swarms[swarmId];
        require(swarm.isActive, "Swarm is not active");

        // Simplified emergent behavior detection
        if (swarm.swarmEvolutionStage >= 3 && swarm.collectiveIntelligence > 1000) {
            swarm.emergentBehavior = "Advanced problem-solving capabilities detected";
            emit EmergentBehaviorDetected(swarmId, swarm.emergentBehavior);
        }
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
        // Implementation of function execution based on the function name
        // This is a simplified version and would need to be expanded based on the actual function implementations
        if (keccak256(abi.encodePacked(functionName)) == keccak256(abi.encodePacked("web_search"))) {
            // Perform web search
        } else if (keccak256(abi.encodePacked(functionName)) == keccak256(abi.encodePacked("image_generation"))) {
            // Generate image
        } else if (keccak256(abi.encodePacked(functionName)) == keccak256(abi.encodePacked("collaborate"))) {
            // Collaborate with another agent
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

    function initiateAgentCollaboration(uint256 initiatorAgentId, uint256 targetAgentId, string memory message) external {
        require(agents[initiatorAgentId].isActive && agents[targetAgentId].isActive, "Both agents must be active");
        
        agents[initiatorAgentId].collaborators.push(targetAgentId);
        agents[targetAgentId].collaborators.push(initiatorAgentId);
        
        IOracle.Message memory collaborationMessage = IOracle.Message({
            role: "system",
            content: new IOracle.Content[](1)
        });
        collaborationMessage.content[0] = IOracle.Content({
            contentType: "text",
            value: string(abi.encodePacked("Collaboration request from Agent ", uint2str(initiatorAgentId), ": ", message))
        });
        agents[targetAgentId].messages.push(collaborationMessage);
        
        emit AgentCollaboration(initiatorAgentId, targetAgentId, message);
        
        IOracle(oracleAddress).createOpenAiLlmCall(targetAgentId, config);
    }

    function advancedLlmCall(uint256 agentId, string memory prompt, string memory systemInstruction) external {
        require(agents[agentId].isActive, "Agent is not active");
        
        IOracle.Message[] memory messages = new IOracle.Message[](2);
        
        messages[0] = IOracle.Message({
            role: "system",
            content: new IOracle.Content[](1)
        });
        messages[0].content[0] = IOracle.Content({
            contentType: "text",
            value: systemInstruction
        });
        
        messages[1] = IOracle.Message({
            role: "user",
            content: new IOracle.Content[](1)
        });
        messages[1].content[0] = IOracle.Content({
            contentType: "text",
            value: prompt
        });
        
        for (uint i = 0; i < messages.length; i++) {
            agents[agentId].messages.push(messages[i]);
        }
        
        IOracle.OpenAiRequest memory customConfig = config;
        customConfig.model = "gpt-4o";
        
        IOracle(oracleAddress).createOpenAiLlmCall(agentId, customConfig);
    }

    function swarmDecisionMaking(uint256 swarmId, string memory decision) external {
        Swarm storage swarm = swarms[swarmId];
        require(swarm.isActive, "Swarm is not active");
        
        uint256 agreeCount = 0;
        uint256 totalVotes = 0;
        
        for (uint i = 0; i < swarm.agentIds.length; i++) {
            uint256 agentId = swarm.agentIds[i];
            if (agents[agentId].isActive) {
                // Simulate agent voting (in a real scenario, this would involve LLM calls)
                if (agents[agentId].autonomyLevel > 5) {
                    agreeCount++;
                }
                totalVotes++;
            }
        }
        
        if (agreeCount > totalVotes / 2) {
            swarm.sharedMemory["lastDecision"] = decision;
            emit SwarmStateChanged(swarmId, SwarmState.Performing);
        } else {
            emit SwarmStateChanged(swarmId, SwarmState.Storming);
        }
    }

    function performKnowledgeSynthesis(string[] memory sources) internal returns (string memory) {
        require(sources.length > 0, "No knowledge sources provided");

        string[] memory retrievedContents = new string[](sources.length);
        for (uint i = 0; i < sources.length; i++) {
            retrievedContents[i] = retrieveFromKnowledgeBase(sources[i]);
        }

        IOracle.Message memory synthesisMessage = IOracle.Message({
            role: "system",
            content: new IOracle.Content[](sources.length + 1)
        });

        synthesisMessage.content[0] = IOracle.Content({
            contentType: "text",
            value: "Synthesize the following knowledge sources into a cohesive and comprehensive knowledge base:"
        });

        for (uint i = 0; i < retrievedContents.length; i++) {
            synthesisMessage.content[i + 1] = IOracle.Content({
                contentType: "text",
                value: retrievedContents[i]
            });
        }

        IOracle.OpenAiRequest memory synthesisConfig = config;
        synthesisConfig.model = "gpt-4o";
        synthesisConfig.maxTokens = 3000;
        synthesisConfig.temperature = 7;

        uint256 synthesisCallbackId = nextAgentId++;
        agents[synthesisCallbackId].isActive = true;

        IOracle(oracleAddress).createOpenAiLlmCall(synthesisCallbackId, synthesisConfig);

        string memory synthesizedKnowledge = waitForSynthesisResponse(synthesisCallbackId);

        delete agents[synthesisCallbackId];

        updateGlobalKnowledgeBase(synthesizedKnowledge);

        return synthesizedKnowledge;
    }

    function retrieveFromKnowledgeBase(string memory source) internal view returns (string memory) {
        return string(abi.encodePacked("Retrieved content from source: ", source));
    }

    function waitForSynthesisResponse(uint256 callbackId) internal view returns (string memory) {
        return "Synthesized knowledge from multiple sources, incorporating various specializations and insights.";
    }

    function handleKnowledgeSynthesisResponse(uint256 callbackId, IOracle.OpenAiResponse memory response) internal {
        string memory synthesizedKnowledge = response.content;
        
        updateGlobalKnowledgeBase(synthesizedKnowledge);
        
        updateAllAgentsWithNewKnowledge(synthesizedKnowledge);
        
        emit KnowledgeSynthesisCompleted(callbackId, synthesizedKnowledge);
    }

    function updateAllAgentsWithNewKnowledge(string memory newKnowledge) internal {
        for (uint256 i = 0; i < nextAgentId; i++) {
            if (agents[i].isActive) {
                agents[i].knowledgeBaseCID = newKnowledge;
                emit KnowledgeBaseUpdated(i, newKnowledge);
            }
        }
    }

    function initiateCollaborativeProblemSolving(uint256 swarmId, string memory problem) external {
        Swarm storage swarm = swarms[swarmId];
        require(swarm.isActive, "Swarm is not active");

        string[] memory subTasks = divideProblem(problem, swarm.agentIds.length);

        for (uint256 i = 0; i < swarm.agentIds.length; i++) {
            assignSubTask(swarm.agentIds[i], subTasks[i], swarm.swarmSpecializations[i]);
        }

        initiateCollaboration(swarmId, problem);
    }

    function divideProblem(string memory problem, uint256 agentCount) internal returns (string[] memory) {
        string[] memory subTasks = new string[](agentCount);
        for (uint256 i = 0; i < agentCount; i++) {
            subTasks[i] = string(abi.encodePacked("Subtask ", uint2str(i + 1), " of problem: ", problem));
        }
        return subTasks;
    }

    function assignSubTask(uint256 agentId, string memory subTask, string memory specialization) internal {
        string memory prompt = string(abi.encodePacked(
            "As a specialist in ", specialization, ", your task is to solve the following sub-problem: ",
            subTask, "\n\nProvide a detailed solution based on your expertise."
        ));

        IOracle.Message memory taskMessage = IOracle.Message({
            role: "user",
            content: new IOracle.Content[](1)
        });
        taskMessage.content[0] = IOracle.Content({
            contentType: "text",
            value: prompt
        });

        agents[agentId].messages.push(taskMessage);
        IOracle(oracleAddress).createOpenAiLlmCall(agentId, config);
    }

    function initiateCollaboration(uint256 swarmId, string memory problem) internal {
        Swarm storage swarm = swarms[swarmId];

        string memory collaborationPrompt = string(abi.encodePacked(
            "Collaborative problem-solving for: ", problem,
            "\n\nEach agent should share their insights and partial solutions. ",
            "Work together to integrate your specialized knowledge and create a comprehensive solution."
        ));

        for (uint256 i = 0; i < swarm.agentIds.length; i++) {
            IOracle.Message memory collabMessage = IOracle.Message({
                role: "system",
                content: new IOracle.Content[](1)
            });
            collabMessage.content[0] = IOracle.Content({
                contentType: "text",
                value: collaborationPrompt
            });

            agents[swarm.agentIds[i]].messages.push(collabMessage);
            IOracle(oracleAddress).createOpenAiLlmCall(swarm.agentIds[i], config);
        }
    }

    function processMultimodalOutput(uint256 agentId, string memory textContent, string memory imagePrompt) external {
        require(agents[agentId].isActive, "Agent is not active");

        // Process text output
        IOracle.Message memory textMessage = IOracle.Message({
            role: "assistant",
            content: new IOracle.Content[](1)
        });
        textMessage.content[0] = IOracle.Content({
            contentType: "text",
            value: textContent
        });
        agents[agentId].messages.push(textMessage);

        // Generate image based on the prompt
        IOracle.OpenAiRequest memory imageConfig = config;
        imageConfig.tools = "[{\"type\":\"function\",\"function\":{\"name\":\"image_generation\",\"description\":\"Generates an image using Dalle-2\",\"parameters\":{\"type\":\"object\",\"properties\":{\"prompt\":{\"type\":\"string\",\"description\":\"Dalle-2 prompt to generate an image\"}},\"required\":[\"prompt\"]}}}]";
        
        IOracle(oracleAddress).createFunctionCall(agentId, "image_generation", imagePrompt);

        emit MultimodalInteractionProcessed(agentId, ["text", "image"]);
    }

    function onOracleFunctionResponse(
        uint256 agentId,
        string memory functionName,
        string memory response,
        string memory errorMessage
    ) external {
        require(msg.sender == oracleAddress, "Only oracle can call this function");

        if (keccak256(abi.encodePacked(functionName)) == keccak256(abi.encodePacked("image_generation"))) {
            if (bytes(errorMessage).length == 0) {
                IOracle.Message memory imageMessage = IOracle.Message({
                    role: "assistant",
                    content: new IOracle.Content[](1)
                });
                imageMessage.content[0] = IOracle.Content({
                    contentType: "image_url",
                    value: response
                });
                agents[agentId].messages.push(imageMessage);
            } else {
                emit AgentResponse(agentId, errorMessage);
            }
        }
        // Handle other function responses as needed
    }

    function uint2str(uint256 _i) internal pure returns (string memory str) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }
        str = string(bstr);
    }

    // Additional events
    event KnowledgeSynthesisCompleted(uint256 callbackId, string synthesizedKnowledge);
    event CollaborativeProblemSolvingInitiated(uint256 swarmId, string problem);
    event SubTaskAssigned(uint256 agentId, string subTask, string specialization);
}

}