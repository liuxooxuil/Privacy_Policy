// SPDX-License-Identifier: GPL-3.0
/*
    Copyright 2021 0KIMS association.

    This file is generated with [snarkJS](https://github.com/iden3/snarkjs).

    snarkJS is a free software: you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    snarkJS is distributed in the hope that it will be useful, but WITHOUT
    ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
    or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public
    License for more details.

    You should have received a copy of the GNU General Public License
    along with snarkJS. If not, see <https://www.gnu.org/licenses/>.
*/

// 本机生成的 pot13 加单方 phase-2，仅用于测试网功能验证。
// 不是 Hermez 公开仪式。主网使用前必须替换本文件。中间 zkey 已在构建时删除，但构建机器仍被信任。
pragma solidity >=0.7.0 <0.9.0;

contract ShieldVerifier {
    // Scalar field size
    uint256 constant r    = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    // Base field size
    uint256 constant q   = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    // Verification Key data
    uint256 constant alphax  = 9617910001306815527602741425665699013532523756292886655412320518521932155451;
    uint256 constant alphay  = 14937239763383784793016559713184613988690718755891492345583713672415392372758;
    uint256 constant betax1  = 1900540371272560162608019766036669801658823980523006562461753996393075001958;
    uint256 constant betax2  = 19011327223674221591236391943759396621028824309405619528417536143718775478536;
    uint256 constant betay1  = 8292492450351742100175245634250591837744849918609040327864764292380423348790;
    uint256 constant betay2  = 17591258136547652709153645465247810449887413436503891720346721341661442853725;
    uint256 constant gammax1 = 11559732032986387107991004021392285783925812861821192530917403151452391805634;
    uint256 constant gammax2 = 10857046999023057135944570762232829481370756359578518086990519993285655852781;
    uint256 constant gammay1 = 4082367875863433681332203403145435568316851327593401208105741076214120093531;
    uint256 constant gammay2 = 8495653923123431417604973247489272438418190587263600148770280649306958101930;
    uint256 constant deltax1 = 20019792564821395476088842036741192613284920746286581760317761341327588142367;
    uint256 constant deltax2 = 14641679938466326064210746085706202008672879938836129290705385065707817682510;
    uint256 constant deltay1 = 17451632734905485652657509811297553650840100378694138847545664309528767828320;
    uint256 constant deltay2 = 13231569938804276294598708989782841834593750565971101238011238571932145495848;

    
    uint256 constant IC0x = 10963198491005861279290513790703853313222394902637224625835583639342618994752;
    uint256 constant IC0y = 491060870960964172945099369207440237552065188031133714866550167243367055019;
    
    uint256 constant IC1x = 1396229073996577589886977834295912325452797303720616284883346244849013933157;
    uint256 constant IC1y = 5542931115338416533123674277324612376564950238832217564787248841274717844079;
    
    uint256 constant IC2x = 10406688755781840966965289240949197217158516200398247390481799383092394983633;
    uint256 constant IC2y = 6662225410022022865655104026002320776059786768023897025844267147777555591813;
    
    uint256 constant IC3x = 7468286905500865658270644767427947948850444332943548108592927649728722827754;
    uint256 constant IC3y = 534907714856326196892665807778383684025515825635498448735417006464414249739;
    
    uint256 constant IC4x = 20736464714067278611712326588959240572393098482962412198424148883155585630555;
    uint256 constant IC4y = 5196456368549889533879518981034267934676267395380910398835446431842126068654;
    
    uint256 constant IC5x = 16512592031804520537642674454543287928014405460301343044234518962519347499226;
    uint256 constant IC5y = 17411495561319640530000413859586455308860046875941295319450652002278169448982;
    
    uint256 constant IC6x = 10627243437189761876024093219021905609973317614129678873664589163112140873361;
    uint256 constant IC6y = 19137905095592911006999285263137625538389985338661241552058985717979844049640;
    
    uint256 constant IC7x = 12324620691461980474312334338098697109990816717839246562241186571198683706580;
    uint256 constant IC7y = 15371133728559385765007585016670611564865569336021180663683774975590461736323;
    
    uint256 constant IC8x = 6917906437428135623858256353761315156653758881168576707655903470843148702102;
    uint256 constant IC8y = 8871544317268597765149756129580717190722923942700736575246545724480222109709;
    
    uint256 constant IC9x = 18737654054023888388093433237096629913360218897207659431798302958337954481485;
    uint256 constant IC9y = 3338344489402287889174661173865796626993245672318163549909924683610499645854;
    
 
    // Memory data
    uint16 constant pVk = 0;
    uint16 constant pPairing = 128;

    uint16 constant pLastMem = 896;

    function verifyProof(uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[9] calldata _pubSignals) public view returns (bool) {
        assembly {
            function checkField(v) {
                if iszero(lt(v, r)) {
                    mstore(0, 0)
                    return(0, 0x20)
                }
            }
            
            // G1 function to multiply a G1 value(x,y) to value in an address
            function g1_mulAccC(pR, x, y, s) {
                let success
                let mIn := mload(0x40)
                mstore(mIn, x)
                mstore(add(mIn, 32), y)
                mstore(add(mIn, 64), s)

                success := staticcall(sub(gas(), 2000), 7, mIn, 96, mIn, 64)

                if iszero(success) {
                    mstore(0, 0)
                    return(0, 0x20)
                }

                mstore(add(mIn, 64), mload(pR))
                mstore(add(mIn, 96), mload(add(pR, 32)))

                success := staticcall(sub(gas(), 2000), 6, mIn, 128, pR, 64)

                if iszero(success) {
                    mstore(0, 0)
                    return(0, 0x20)
                }
            }

            function checkPairing(pA, pB, pC, pubSignals, pMem) -> isOk {
                let _pPairing := add(pMem, pPairing)
                let _pVk := add(pMem, pVk)

                mstore(_pVk, IC0x)
                mstore(add(_pVk, 32), IC0y)

                // Compute the linear combination vk_x
                
                g1_mulAccC(_pVk, IC1x, IC1y, calldataload(add(pubSignals, 0)))
                
                g1_mulAccC(_pVk, IC2x, IC2y, calldataload(add(pubSignals, 32)))
                
                g1_mulAccC(_pVk, IC3x, IC3y, calldataload(add(pubSignals, 64)))
                
                g1_mulAccC(_pVk, IC4x, IC4y, calldataload(add(pubSignals, 96)))
                
                g1_mulAccC(_pVk, IC5x, IC5y, calldataload(add(pubSignals, 128)))
                
                g1_mulAccC(_pVk, IC6x, IC6y, calldataload(add(pubSignals, 160)))
                
                g1_mulAccC(_pVk, IC7x, IC7y, calldataload(add(pubSignals, 192)))
                
                g1_mulAccC(_pVk, IC8x, IC8y, calldataload(add(pubSignals, 224)))
                
                g1_mulAccC(_pVk, IC9x, IC9y, calldataload(add(pubSignals, 256)))
                

                // -A
                mstore(_pPairing, calldataload(pA))
                mstore(add(_pPairing, 32), mod(sub(q, calldataload(add(pA, 32))), q))

                // B
                mstore(add(_pPairing, 64), calldataload(pB))
                mstore(add(_pPairing, 96), calldataload(add(pB, 32)))
                mstore(add(_pPairing, 128), calldataload(add(pB, 64)))
                mstore(add(_pPairing, 160), calldataload(add(pB, 96)))

                // alpha1
                mstore(add(_pPairing, 192), alphax)
                mstore(add(_pPairing, 224), alphay)

                // beta2
                mstore(add(_pPairing, 256), betax1)
                mstore(add(_pPairing, 288), betax2)
                mstore(add(_pPairing, 320), betay1)
                mstore(add(_pPairing, 352), betay2)

                // vk_x
                mstore(add(_pPairing, 384), mload(add(pMem, pVk)))
                mstore(add(_pPairing, 416), mload(add(pMem, add(pVk, 32))))


                // gamma2
                mstore(add(_pPairing, 448), gammax1)
                mstore(add(_pPairing, 480), gammax2)
                mstore(add(_pPairing, 512), gammay1)
                mstore(add(_pPairing, 544), gammay2)

                // C
                mstore(add(_pPairing, 576), calldataload(pC))
                mstore(add(_pPairing, 608), calldataload(add(pC, 32)))

                // delta2
                mstore(add(_pPairing, 640), deltax1)
                mstore(add(_pPairing, 672), deltax2)
                mstore(add(_pPairing, 704), deltay1)
                mstore(add(_pPairing, 736), deltay2)


                let success := staticcall(sub(gas(), 2000), 8, _pPairing, 768, _pPairing, 0x20)

                isOk := and(success, mload(_pPairing))
            }

            let pMem := mload(0x40)
            mstore(0x40, add(pMem, pLastMem))

            // Validate that all evaluations ∈ F
            
            checkField(calldataload(add(_pubSignals, 0)))
            
            checkField(calldataload(add(_pubSignals, 32)))
            
            checkField(calldataload(add(_pubSignals, 64)))
            
            checkField(calldataload(add(_pubSignals, 96)))
            
            checkField(calldataload(add(_pubSignals, 128)))
            
            checkField(calldataload(add(_pubSignals, 160)))
            
            checkField(calldataload(add(_pubSignals, 192)))
            
            checkField(calldataload(add(_pubSignals, 224)))
            
            checkField(calldataload(add(_pubSignals, 256)))
            

            // Validate all evaluations
            let isValid := checkPairing(_pA, _pB, _pC, _pubSignals, pMem)

            mstore(0, isValid)
             return(0, 0x20)
         }
     }
 }
