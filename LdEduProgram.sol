// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract LdEduProgram is Ownable, ReentrancyGuard {

    // 이벤트 정의
    event ProgramCreated(uint256 indexed id, address indexed maker, address indexed validator, uint256 price);
    event ProgramApproved(uint256 indexed id, address builder);
    event ProgramClaimed(uint256 indexed id, address builder, uint256 amount);
    event FundsReclaimed(uint256 indexed id, address maker, uint256 amount);
    event ValidatorUpdated(uint256 indexed id, address newValidator);
    event FeeUpdated(uint256 newFee);

    // 그랜츠 프로그램 구조체 (EduProgram)
    struct EduProgram {
        uint256 id;          // 프로그램 유니크 아이디
        string name;         // 프로그램 이름
        uint256 price;       // 예치 금액 (wei 단위)
        uint256 startTime;   // 프로그램 시작 시간 (unix time)
        uint256 endTime;     // 프로그램 종료 시간 (unix time)
        address maker;       // 프로그램 생성자
        address validator;   // 승인 권한을 가진 벨리데이터
        bool approve;        // 승인 여부
        bool claimed;        // 이미 청구 또는 회수되었는지 여부
        address builder;     // 승인 후 청구할 빌더 주소
    }

    // 벨리데이터 변경을 위한 구조체 (필요 시 활용)
    struct ValAddr {
        uint256 programId;
        bool isValidator;
    }

    // 프로그램 저장소: 프로그램 id -> EduProgram
    mapping(uint256 => EduProgram) public eduPrograms;
    uint256 public nextProgramId;

    // 수수료 (fee는 basis point 단위, 예: 100 = 1% 수수료)
    uint256 private fee;

    constructor(address initialOwner) Ownable(initialOwner) {
    }

    /**
     * @notice 프로그램 생성 함수
     * @param _name 프로그램 이름
     * @param _price 프로그램 금액 (wei 단위)
     * @param _startTime 프로그램 시작 시간 (unix time)
     * @param _endTime 프로그램 종료 시간 (unix time)
     * @param _validator 승인할 벨리데이터 주소
     *
     * 생성 시 msg.sender는 예치금(_price) 만큼 ETH를 전송해야 하며,
     * 프로그램 정보가 저장되고 이후 벨리데이터가 승인할 수 있도록 설정됩니다.
     */
    function createEduProgram(
        string memory _name,
        uint256 _price,
        uint256 _startTime,
        uint256 _endTime,
        address _validator
    ) external payable {
        require(msg.value == _price, "The ETH sent does not match the program price");
        require(_startTime < _endTime, "The Start time must be earlier than the end time.");
        uint256 programId = nextProgramId;
  
        eduPrograms[programId] = EduProgram({
            id: programId,
            name: _name,
            price: _price,
            startTime: _startTime,
            endTime: _endTime,
            maker: msg.sender,
            validator: _validator,
            approve: false,
            claimed: false,
            builder: address(0)
        });
        nextProgramId++;
        emit ProgramCreated(programId, msg.sender, _validator, _price);
    }

    /**
     * @notice 벨리데이터가 프로그램을 승인하는 함수
     * @param programId 프로그램 아이디
     * @param _builder 빌더 주소 (프로그램 수행 후 그랜츠를 청구할 사용자)
     *
     * 승인은 프로그램 종료 시간 전까지 가능하며, 승인 시 빌더 주소가 기록됩니다.
     */
    function approveProgram(uint256 programId, address _builder) external {
        EduProgram storage program = eduPrograms[programId];
        require(msg.sender == program.validator, "You don't have approval permissions.");
        require(block.timestamp <= program.endTime, "The program has already ended. ");
        require(!program.approve, "Already approved.");
        program.approve = true;
        program.builder = _builder;

        emit ProgramApproved(programId, _builder);
    }

    /**
     * @notice 승인된 빌더가 그랜츠를 청구하는 함수
     * @param programId 프로그램 아이디
     *
     * 청구는 프로그램 시작 시간 이후, 종료 시간 이전에만 가능하며,
     * 수수료가 적용될 경우 수수료는 계약 소유자에게 전송됩니다.
     */
    function claimGrants(uint256 programId) external nonReentrant {
        EduProgram storage program = eduPrograms[programId];
        require(program.approve, "The program is not approved.");
        require(!program.claimed, "Already claimed.");
        require(msg.sender == program.builder, "You do not have permission to claim.");
        require(block.timestamp >= program.startTime, "The program has not started yet.");
        require(block.timestamp <= program.endTime, "The program billing period has passed.");

        program.claimed = true;

        uint256 payout = program.price;
        if (fee > 0) {
            uint256 feeAmount = (payout * fee) / 10000;
            payout = payout - feeAmount;
            payable(owner()).transfer(feeAmount);
        }
        payable(program.builder).transfer(payout);

        emit ProgramClaimed(programId, program.builder, payout);
    }

    /**
     * @notice 프로그램 기간 만료 후, 아직 승인되지 않은 경우 제작자가 예치금을 회수하는 함수
     * @param programId 프로그램 아이디
     */
    function reclaimFunds(uint256 programId) external nonReentrant {
        EduProgram storage program = eduPrograms[programId];
        require(!program.approve, "It's already been approved and can't be reclaimed.");
        require(!program.claimed, "Already taken care of.");
        require(block.timestamp > program.endTime, "The program hasn't ended yet.");
        require(msg.sender == program.maker, "You don't have reclamation rights.");

        program.claimed = true;
        payable(program.maker).transfer(program.price);

        emit FundsReclaimed(programId, program.maker, program.price);
    }

    /**
     * @notice 제작자가 승인 벨리데이터를 변경하는 함수
     * @param programId 프로그램 아이디
     * @param newValidator 새로운 벨리데이터 주소
     */
    function updateValidator(uint256 programId, address newValidator) external {
        EduProgram storage program = eduPrograms[programId];
        require(msg.sender == program.maker, "Only creators can change approvers.");
        program.validator = newValidator;

        emit ValidatorUpdated(programId, newValidator);
    }

    /**
     * @notice 계약 소유자가 수수료를 설정하는 함수 (basis point 단위)
     * @param _fee 새로운 수수료 (예: 100 = 1%)
     */
    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
        emit FeeUpdated(_fee);
    }

    /**
     * @notice 현재 설정된 수수료를 반환하는 함수
     */
    function getFee() external view returns (uint256) {
        return fee;
    }
}
