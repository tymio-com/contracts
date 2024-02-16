// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

library ArrayUtils {
    function deleteItem(address[] storage self, address item)
        internal
        returns (bool success)
    {
        uint256 length = self.length;
        for (uint256 i = 0; i < length; i++) {
            if (self[i] == item) {
                uint256 newLength = self.length - 1;
                if (i != newLength) {
                    self[i] = self[newLength];
                }
                self[newLength] = self[self.length - 1];
                self.pop();

                return true;
            }
        }
    }
}
