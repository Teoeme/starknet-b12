#[starknet::interface]
pub trait ICounter<TContractState>  {
    fn increase_counter(ref self: TContractState);
    fn decrease_counter(ref self: TContractState);
    fn get_counter(self: @TContractState) -> u32;
    fn reset_counter(ref self: TContractState);
}


#[starknet::contract]
pub mod Counter {
    use OwnableComponent::InternalTrait;
    use super::ICounter;
    use openzeppelin_access::ownable::OwnableComponent;
    use starknet::{ContractAddress,get_caller_address};
    use starknet::storage::{StoragePointerWriteAccess,StoragePointerReadAccess};


    component!(path:OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl OwneableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState> ;
    impl OwnableTwoStepImpl = OwnableComponent::OwnableTwoStepImpl<ContractState>;
    

    #[storage]
    pub struct Storage {
        counter: u32,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage
    }

    #[constructor]
    fn constructor(ref self: ContractState,init_value: u32,owner:ContractAddress) {
        self.counter.write(init_value);
        self.ownable.initializer(owner)
    }


    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        Increased:Increased,
        Decreased:Decreased,
        #[flat]
        OwnableEvent: OwnableComponent::Event
    }

    #[derive(Drop, starknet::Event)]
    pub struct Increased {
        account:ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    pub struct Decreased {
        account:ContractAddress
    }
    
    pub mod Error {
        pub const EMPTY_COUNTER:felt252 = 'Decreasing an empty counter';
    }

    #[abi(embed_v0)]
    impl CounterImpl of ICounter<ContractState> {
        fn increase_counter(ref self: ContractState) {
            let new_value=self.counter.read() + 1;
            self.counter.write(new_value);
            //event
            self.emit(Increased { account: get_caller_address() });
        }

        fn decrease_counter(ref self: ContractState) {
            let old_value=self.counter.read();
            assert(old_value>0, Error::EMPTY_COUNTER);
            let new_value=old_value - 1;
            self.counter.write(new_value);
            //event
            self.emit(Decreased { account: get_caller_address() });
        }

        fn get_counter(self: @ContractState) -> u32 {
            self.counter.read()
        }

        fn reset_counter(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.counter.write(0);
        }

    }
    
    
}
