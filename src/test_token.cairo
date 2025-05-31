use starknet::ContractAddress;
use starknet::storage::StorageMap;
use starknet::storage::StorageMapReadAccess;
use starknet::storage::StorageMapWriteAccess;
use starknet::storage::StorageValue;
use starknet::storage::StorageValueReadAccess;
use starknet::storage::StorageValueWriteAccess;
use openzeppelin::token::erc20::interface::IERC20;
use openzeppelin::token::erc20::interface::IERC20Metadata;
use openzeppelin::access::ownable::OwnableComponent;

#[starknet::interface]
pub trait ITestToken<T> {
    fn name(self: @T) -> felt252;
    fn symbol(self: @T) -> felt252;
    fn decimals(self: @T) -> u8;
    fn total_supply(self: @T) -> u256;
    fn balance_of(self: @T, account: ContractAddress) -> u256;
    fn allowance(self: @T, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: T, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(ref self: T, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
    fn approve(ref self: T, spender: ContractAddress, amount: u256) -> bool;
    fn mint(ref self: T, to: ContractAddress, amount: u256);
}

#[starknet::contract]
mod TestToken {
    use super::*;
    use starknet::{get_caller_address, get_contract_address};
    use openzeppelin::token::erc20::ERC20Component;
    use openzeppelin::token::erc20::ERC20MetadataComponent;
    use openzeppelin::access::ownable::OwnableComponent;
    
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(
        path: ERC20MetadataComponent,
        storage: erc20_metadata,
        event: ERC20MetadataEvent
    );

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        erc20_metadata: ERC20MetadataComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        OwnableEvent: OwnableComponent::Event,
        ERC20Event: ERC20Component::Event,
        ERC20MetadataEvent: ERC20MetadataComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: felt252,
        symbol: felt252,
        decimals: u8,
        initial_supply: u256,
    ) {
        // Initialize Ownable
        let owner = get_caller_address();
        self.ownable.initializer(owner);
        
        // Initialize ERC20
        self.erc20.initializer(name, symbol);
        
        // Initialize ERC20Metadata
        self.erc20_metadata.initializer(decimals);
        
        // Mint initial supply to the deployer
        self.erc20.mint(owner, initial_supply);
    }
    
    #[external(v0)]
    impl TestTokenImpl of ITestToken<ContractState> {
        // ERC20 functions
        fn name(self: @ContractState) -> felt252 {
            self.erc20.name()
        }
        
        fn symbol(self: @ContractState) -> felt252 {
            self.erc20.symbol()
        }
        
        fn decimals(self: @ContractState) -> u8 {
            self.erc20_metadata.decimals()
        }
        
        fn total_supply(self: @ContractState) -> u256 {
            self.erc20.total_supply()
        }
        
        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            self.erc20.balance_of(account)
        }
        
        fn allowance(self: @ContractState, owner: ContractAddress, spender: ContractAddress) -> u256 {
            self.erc20.allowance(owner, spender)
        }
        
        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            self.erc20.transfer(recipient, amount)
        }
        
        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            self.erc20.transfer_from(sender, recipient, amount)
        }
        
        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            self.erc20.approve(spender, amount)
        }
        
        // Custom mint function for testing
        fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
            self.ownable.assert_only_owner();
            self.erc20.mint(to, amount);
        }
    }
}
