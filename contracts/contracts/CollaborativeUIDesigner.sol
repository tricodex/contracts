// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IOracle.sol";

contract CollaborativeUIDesigner {
    enum AgentRole {
        Coordinator,
        UXDesigner,
        UIDeveloper,
        AccessibilityExpert,
        BrandingSpecialist,
        User
    }

    struct Agent {
        string name;
        string prompt;
        uint8 skillLevel;
    }

    struct UIDesignRun {
        address owner;
        IOracle.Message[] messages;
        uint responsesCount;
        uint8 max_iterations;
        bool is_finished;
        mapping(AgentRole => uint) agentContributions;
        string projectName;
        string projectDescription;
        uint complexity;
        string knowledgeBaseCID;
        string currentDesignCID;
    }

    mapping(uint => UIDesignRun) public uiDesignRuns;
    uint private runCount;

    address private owner;
    address public oracleAddress;

    mapping(AgentRole => Agent) public agents;

    event UIDesignStarted(address indexed owner, uint indexed runId, string projectName);
    event AgentContribution(uint indexed runId, AgentRole agent, string contribution);
    event DesignMilestoneReached(uint indexed runId, string milestone);
    event UIDesignCompleted(uint indexed runId, string projectName, string finalDesignCID);
    event KnowledgeBaseUpdated(uint indexed runId, string newCID);

    IOracle.OpenAiRequest private config;

    constructor(address initialOracleAddress, string memory systemPrompt) {
        owner = msg.sender;
        oracleAddress = initialOracleAddress;
        runCount = 0;

        config = IOracle.OpenAiRequest({
            model: "gpt-4o",
            frequencyPenalty: 21,
            logitBias: "",
            maxTokens: 2000,
            presencePenalty: 21,
            responseFormat: "{\"type\":\"text\"}",
            seed: 0,
            stop: "",
            temperature: 10,
            topP: 101,
            tools: "[{\"type\":\"function\",\"function\":{\"name\":\"web_search\",\"description\":\"Search the internet for UI design trends and best practices\",\"parameters\":{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\",\"description\":\"Search query\"}},\"required\":[\"query\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"image_generation\",\"description\":\"Generate UI mockup images based on text descriptions\",\"parameters\":{\"type\":\"object\",\"properties\":{\"prompt\":{\"type\":\"string\",\"description\":\"Image generation prompt for UI mockup\"}},\"required\":[\"prompt\"]}}},{\"type\":\"function\",\"function\":{\"name\":\"code_interpreter\",\"description\":\"Generate and validate HTML/CSS/JS code for UI components\",\"parameters\":{\"type\":\"object\",\"properties\":{\"code\":{\"type\":\"string\",\"description\":\"UI component code to generate or validate\"}},\"required\":[\"code\"]}}}]",
            toolChoice: "auto",
            user: ""
        });

        initializeAgents(systemPrompt);
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
    }

    function initializeAgents(string memory systemPrompt) private {
        agents[AgentRole.Coordinator] = Agent("Design Orchestrator", systemPrompt, 1);
        agents[AgentRole.UXDesigner] = Agent("Experience Architect", "Focus on user journeys, wireframes, and interaction design to create intuitive and engaging user experiences.", 1);
        agents[AgentRole.UIDeveloper] = Agent("Visual Composer", "Translate UX concepts into visually appealing UI designs and implement them with clean, efficient code.", 1);
        agents[AgentRole.AccessibilityExpert] = Agent("Inclusion Guardian", "Ensure the UI design is accessible to all users, regardless of abilities or devices used.", 1);
        agents[AgentRole.BrandingSpecialist] = Agent("Brand Alchemist", "Infuse the UI design with the project's brand identity, ensuring consistent and compelling visual communication.", 1);
    }

    function startUIDesign(string memory projectName, string memory projectDescription, string memory initialKnowledgeBaseCID, uint8 max_iterations) public returns (uint) {
        uint runId = runCount++;
        UIDesignRun storage run = uiDesignRuns[runId];

        run.owner = msg.sender;
        run.responsesCount = 0;
        run.max_iterations = max_iterations;
        run.is_finished = false;
        run.projectName = projectName;
        run.projectDescription = projectDescription;
        run.complexity = 5;
        run.knowledgeBaseCID = initialKnowledgeBaseCID;
        run.currentDesignCID = "";

        string memory initialPrompt = string(abi.encodePacked(
            "Initiating UI design for project: ", projectName, ". Description: ", projectDescription,
            ". As the Design Orchestrator, begin by outlining the key objectives and design principles for this UI."
        ));

        run.messages.push(createTextMessage("system", agents[AgentRole.Coordinator].prompt));
        run.messages.push(createTextMessage("user", initialPrompt));

        IOracle(oracleAddress).createOpenAiLlmCall(runId, config);
        emit UIDesignStarted(msg.sender, runId, projectName);

        return runId;
    }

    function onOracleOpenAiLlmResponse(
        uint runId,
        IOracle.OpenAiResponse memory response,
        string memory errorMessage
    ) public onlyOracle {
        UIDesignRun storage run = uiDesignRuns[runId];
        require(!run.is_finished, "UI design process is already complete");

        if (bytes(errorMessage).length > 0) {
            run.messages.push(createTextMessage("assistant", errorMessage));
            run.responsesCount++;
            run.is_finished = true;
            emit UIDesignCompleted(runId, run.projectName, run.currentDesignCID);
            return;
        }

        if (run.responsesCount >= run.max_iterations) {
            run.is_finished = true;
            return;
        }

        if (bytes(response.content).length > 0) {
            AgentRole currentRole = determineNextAgent(run);
            run.messages.push(createTextMessage("assistant", response.content));
            run.responsesCount++;
            run.agentContributions[currentRole]++;

            emit AgentContribution(runId, currentRole, response.content);

            if (run.responsesCount % 5 == 0) {
                string memory milestone = generateMilestone(run);
                emit DesignMilestoneReached(runId, milestone);
                run.messages.push(createTextMessage("system", milestone));
                updateKnowledgeBase(runId);
            }

            if (bytes(response.functionName).length > 0) {
                executeTool(runId, response);
            }

            if (run.responsesCount >= 30 || isDesignComplete(run)) {
                run.is_finished = true;
                string memory completionMessage = generateCompletionMessage(run);
                run.messages.push(createTextMessage("system", completionMessage));
                emit UIDesignCompleted(runId, run.projectName, run.currentDesignCID);
            } else {
                string memory nextPrompt = generateNextPrompt(run);
                run.messages.push(createTextMessage("user", nextPrompt));
                IOracle(oracleAddress).createOpenAiLlmCall(runId, config);
            }
        }
    }

    function addUserMessage(uint runId, string memory message) public {
        UIDesignRun storage run = uiDesignRuns[runId];
        require(msg.sender == run.owner, "Only the run owner can add messages");
        require(!run.is_finished, "UI design process is already complete");

        run.messages.push(createTextMessage("user", message));
        IOracle(oracleAddress).createOpenAiLlmCall(runId, config);
    }

    function getMessageHistory(uint runId) public view returns (IOracle.Message[] memory) {
        return uiDesignRuns[runId].messages;
    }

    function isRunFinished(uint runId) public view returns (bool) {
        return uiDesignRuns[runId].is_finished;
    }

    function determineNextAgent(UIDesignRun storage run) private view returns (AgentRole) {
        uint8 agentCount = uint8(type(AgentRole).max) - 1;
        uint256 seed = uint256(keccak256(abi.encodePacked(block.timestamp, run.responsesCount, run.complexity)));
        
        AgentRole selectedRole;
        uint highestScore = 0;

        for (uint8 i = 0; i < agentCount; i++) {
            AgentRole role = AgentRole(i);
            uint score = calculateAgentScore(run, role, seed);
            if (score > highestScore) {
                highestScore = score;
                selectedRole = role;
            }
        }

        return selectedRole;
    }

    function calculateAgentScore(UIDesignRun storage run, AgentRole role, uint256 seed) private view returns (uint) {
        uint baseScore = uint(agents[role].skillLevel) * 100;
        uint contributionBonus = run.agentContributions[role] * 10;
        uint randomFactor = seed % 100;
        
        if (role == AgentRole.UXDesigner && run.responsesCount < 10) baseScore += 50;
        if (role == AgentRole.UIDeveloper && run.responsesCount > 15) baseScore += 75;
        if (role == AgentRole.AccessibilityExpert && run.complexity > 7) baseScore += 100;
        
        return baseScore + contributionBonus + randomFactor;
    }

    function generateMilestone(UIDesignRun storage run) private view returns (string memory) {
        string[5] memory milestones = [
            "User journey mapped and wireframes created",
            "Initial UI mockups generated",
            "Accessibility features implemented",
            "Brand identity integrated into design",
            "Final UI components coded and validated"
        ];
        return string(abi.encodePacked("Milestone reached for ", run.projectName, ": ", milestones[run.responsesCount / 5 % 5]));
    }

    function updateKnowledgeBase(uint runId) private {
        UIDesignRun storage run = uiDesignRuns[runId];
        
        string memory updateQuery = string(abi.encodePacked(
            "Update knowledge base for project ", run.projectName,
            " with latest design insights from step ", uint2str(run.responsesCount)
        ));

        IOracle(oracleAddress).createKnowledgeBaseQuery(
            runId,
            run.knowledgeBaseCID,
            updateQuery,
            3
        );
    }

    function executeTool(uint runId, IOracle.OpenAiResponse memory response) private {
        IOracle(oracleAddress).createFunctionCall(
            runId,
            response.functionName,
            response.functionArguments
        );
    }

    function onOracleFunctionResponse(
        uint runId,
        string memory response,
        string memory errorMessage
    ) public onlyOracle {
        UIDesignRun storage run = uiDesignRuns[runId];
        require(!run.is_finished, "Run is finished");

        string memory result = bytes(errorMessage).length > 0 ? errorMessage : response;

        if (bytes(result).length > 7 && keccak256(bytes(substring(result, 0, 7))) == keccak256(bytes("ipfs://"))) {
            run.currentDesignCID = substring(result, 7, bytes(result).length);
        }

        run.messages.push(createTextMessage("user", result));
        run.responsesCount++;
        IOracle(oracleAddress).createOpenAiLlmCall(runId, config);
    }

    function isDesignComplete(UIDesignRun storage run) private view returns (bool) {
        bool hasAllComponents = run.agentContributions[AgentRole.UXDesigner] >= 5 &&
                                run.agentContributions[AgentRole.UIDeveloper] >= 5 &&
                                run.agentContributions[AgentRole.AccessibilityExpert] >= 3 &&
                                run.agentContributions[AgentRole.BrandingSpecialist] >= 3;
        
        bool hasDesignCID = bytes(run.currentDesignCID).length > 0;
        bool sufficientSteps = run.responsesCount >= 25;

        return hasAllComponents && hasDesignCID && sufficientSteps;
    }

    function generateCompletionMessage(UIDesignRun storage run) private view returns (string memory) {
        return string(abi.encodePacked(
            "Congratulations! The UI design for ", run.projectName, " is complete. ",
            "The final design can be accessed at: ipfs://", run.currentDesignCID, ". ",
            "This collaborative AI-driven process has resulted in a user-centric, accessible, and visually appealing interface. ",
            "Key statistics: ",
            "UX Contributions: ", uint2str(run.agentContributions[AgentRole.UXDesigner]), ", ",
            "UI Development: ", uint2str(run.agentContributions[AgentRole.UIDeveloper]), ", ",
            "Accessibility Checks: ", uint2str(run.agentContributions[AgentRole.AccessibilityExpert]), ", ",
            "Branding Integrations: ", uint2str(run.agentContributions[AgentRole.BrandingSpecialist]), ". ",
            "The design is ready for implementation and user testing."
        ));
    }

    function generateNextPrompt(UIDesignRun storage run) private view returns (string memory) {
        string[5] memory prompts = [
            "Analyze the current user flow and suggest improvements based on the latest UX trends. Consider the project's unique requirements and user demographics.",
            "Design a key UI component that enhances both visual appeal and usability. Focus on innovative interaction patterns and alignment with the brand identity.",
            "Review the current design for accessibility. Ensure it meets WCAG 2.1 AA standards and propose enhancements for inclusive user experience.",
            "Integrate brand elements to strengthen the visual identity. Consider color psychology, typography, and iconography that resonate with the target audience.",
            "Generate optimized code for the most critical UI component. Ensure responsiveness, performance, and cross-browser compatibility."
        ];
        
        return prompts[run.responsesCount % 5];
    }

    function onOracleKnowledgeBaseQueryResponse(
        uint runId,
        string[] memory documents,
        string memory errorMessage
    ) public onlyOracle {
        UIDesignRun storage run = uiDesignRuns[runId];
        if (bytes(errorMessage).length == 0 && documents.length > 0) {
            run.knowledgeBaseCID = documents[0];
            emit KnowledgeBaseUpdated(runId, run.knowledgeBaseCID);
        } else {
            run.messages.push(createTextMessage("system", string(abi.encodePacked("Knowledge base update error: ", errorMessage))));
        }
        IOracle(oracleAddress).createOpenAiLlmCall(runId, config);
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

    function uint2str(uint _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len;
        while (_i != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function substring(string memory str, uint startIndex, uint endIndex) private pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }
}