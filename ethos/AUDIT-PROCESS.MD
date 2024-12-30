PROCESS ONE WORLD


1 - Read detail about the contest (Youtube, Discord, ReadMe)
	Description : One World Project is a dynamic DAO marketplace
			- clone the project : git clone https://xxxxxx : OK
			- ReadMe on the contest page : OK
			- Read the documenttation % web site : OK
			- Read ReadMe of the code source : OK
			- compile the project and run test : OK
			- Read doc inside the project github : OK
			- watch the video : OK



2- Look at the architecture of the project
			- compile the project : ok
			- run the test  : ok , npm run test:contracts
			- solidity version : 0.8.26
			- Token : ERC721, ERC20 , USDC , WETH , WBTC
			- Blockchain : EVM Base



3 - Metrics
		Run solidity Metrics
			- NSLOC : 586
			- Complexity : 503
			- Capability : Receive funds
			- Import : see Check section


4 - Role & Actors
		list All roles and Actors with what function theire are calling : be short maximum in 2 lines for each role & actors
         - Administrators: Manage market configurations, graduation, and authorizations (e.g., addMarketConfig, graduateMarket).
         - Users: Create markets and participate in vote trading (e.g., createMarketWithConfig, buyVotes, sellVotes).
         - Profile Owners: Receive donations and can update associated markets (e.g., updateDonationRecipient).


5 - Read rapidly the code , documenation provided and see if the code is doing what the comment of the function indicated.
			- Explain each function and the purpose of each function internal, public, external, private
			- List all part where the code is not doing what is stipulate in the comment or description
			- List all kind of possible vulnerability you see in the function
			- don't display the code
			- For each function try to write a details informatiosn so I could understand
			- For each function add the name of the contract , the name of the function , return argument, modifier , visilibity
			- Do not forget any function , list them all
			- Fllow absolutly all my instrcution

6 - Read the Discord page and write interesting finding
			- OK

7 - Read Vulnerabilities
		- Read the list of vulnerabilities et note all possible problem in finding or @audit : ok

8 - Run Slither aderyn and laayze4

		- Slither

			slither --exclude-dependencies  .  --checklist  > Slither-Report.md
			mkdir graph_dot
			slither --exclude-dependencies  . --print call-graph
			mv ./*.dot graph_dot/

		- Aderyn

			aderyn .

		- Read Slither, Aderyn, LightChaser Reports : OK
		- Check some information  :
      		-  internal state writing code
      		-  see where the money enter in the system
      		-  see where the money is leaving the system
      		-


9 -  Run  the coverage  or convert hardat to foundry
				- forge coverage --ir-minimum > coverage_test.log
				- forge coverage --report debug > coverage_debug.log
				- forge coverage --mc StablecoinTest --report debug > coverage-contract_contract.log
				- forge coverage  --match-contract PreMarketsAdminTest --report debug --ir-minimum > report_coverage.log
		- Resulat below


10 - Read the Test and run , reading the code in the same time
		-  Read the test and put the code of each function in Chatgpt by asking. : Can you explain to me how the following method works and tell me what vulnerabilities you see in this method (explique moi ce code en franacais et trouve moi les vulnerabilité. : )


11 - Generate test to have 100 % of coverage code , function and branch




################################### INVARIANT ####################################################


################################### SECTION 3 IMPORT   ###################################################
@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol
@openzeppelin/contracts/utils/ReentrancyGuard.sol
@openzeppelin/contracts/utils/math/Math.sol
@prb/math/src/UD60x18.sol
