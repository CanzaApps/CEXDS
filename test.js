const fs = require('fs');

let total = 0;

function countLinesInFile(filePath, name) {
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  const lines = fileContent.split('\n');
  let count = 0;

  for (let i = 0; i < lines.length; i++) {
    if (lines[i].trim() !== '' && lines[i][0] !== '/') {
      count++;
    }
  }
   total += count;
  return console.log(`${name} lines: ${count}`);
}

// Example usage
const crds = './contracts/cexDS/CEXDefaultSwap.sol';
const Oracle = './contracts/cexDS/Oracle.sol';
const Voting = './contracts/cexDS/Voting.sol';
const SwapController = './contracts/cexDS/SwapController.sol';
const icrds = './contracts/cexDS/interfaces/ICreditDefaultSwap.sol';
const ioracle = './contracts/cexDS/interfaces/IOracle.sol';
const iswapctl = './contracts/cexDS/interfaces/ISwapController.sol';

countLinesInFile(crds, "CEXDefaultSwap");
countLinesInFile(Oracle, "Oracle");
countLinesInFile(Voting, "Voting");
countLinesInFile(SwapController, "SwapController");
countLinesInFile(icrds, "ICreditDefaultSwap");
countLinesInFile(ioracle, "IOracle");
countLinesInFile(iswapctl, "SwapController");
console.log(`Total lines in files: ${total}`);
