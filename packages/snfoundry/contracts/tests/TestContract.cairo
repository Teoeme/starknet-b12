use contracts::Counter::{Counter, ICounterDispatcher, ICounterDispatcherTrait,ICounterSafeDispatcher,ICounterSafeDispatcherTrait};
use openzeppelin_access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use openzeppelin_access::ownable::{OwnableComponent};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, spy_events, start_cheat_caller_address,
    stop_cheat_caller_address, EventSpyAssertionsTrait
};
use starknet::ContractAddress;



const ZERO_COUNT: u32 = 0;
fn OWNER() -> ContractAddress {
    'OWNER'.try_into().unwrap()
}

fn USER_1() -> ContractAddress {
    'USER_1'.try_into().unwrap()
}

//util deploy function

fn __deploy__(init_value: u32) -> (ICounterDispatcher, IOwnableDispatcher,ICounterSafeDispatcher) {
    let contractClass = declare("Counter").unwrap().contract_class();

    //serialize calldata
    let mut calldata: Array<felt252> = array![];

    init_value.serialize(ref calldata);
    OWNER().serialize(ref calldata);

    //deploy contract
    let (contract_address, _) = contractClass.deploy(@calldata).expect('Deploy failed');

    let counter = ICounterDispatcher { contract_address };
    let ownable = IOwnableDispatcher { contract_address };
    let safe_dispatcher = ICounterSafeDispatcher { contract_address };

    (counter, ownable, safe_dispatcher)
}

#[test]
fn test_counter_deployment() {
    let (counter, ownable, _) = __deploy__(0);

    //count 1
    let count_1 = counter.get_counter();

    assert(count_1 == ZERO_COUNT, 'Counter should be 0');
    assert(ownable.owner() == OWNER(), 'Owner not set');
}

#[test]
fn test_increase_counter() {
    let (counter, _ , _) = __deploy__(ZERO_COUNT);

    let count_1 = counter.get_counter();

    assert(count_1 == ZERO_COUNT, 'Counter should be 0');

    //increase counter
    counter.increase_counter();

    let count_2 = counter.get_counter();
    assert(count_2 == count_1 + 1, 'Invalid count');
}

#[test]
fn test_emitted_increased_event() {
    let (counter, _ , _) = __deploy__(ZERO_COUNT);
    let mut spy = spy_events();

    //mock a caller
    start_cheat_caller_address(counter.contract_address, USER_1());
    counter.increase_counter();
    stop_cheat_caller_address(counter.contract_address);
    spy.assert_emitted(
            @array![
                (counter.contract_address,
                 Counter::Event::Increased (
                    Counter::Increased {
                        account: USER_1()
                    }
                 )
                )],
        );

        spy.assert_not_emitted(
            @array![
                (
                counter.contract_address, 
                 Counter::Event::Decreased(
                    Counter::Decreased {
                        account: USER_1()
                    }
                 ),
                ),
            ]
        )
}


#[test]
#[feature("safe_dispatcher")]
fn test_safe_panic_decrease_counter() {

    let (counter, _ , safe_dispatcher) = __deploy__(ZERO_COUNT);
    assert(counter.get_counter() == ZERO_COUNT, 'Invalid count');

    match safe_dispatcher.decrease_counter() {
        Result::Ok(_) => panic!("cannot decrease 0"),
        Result::Err(e) => assert(*e[0] == Counter::Error::EMPTY_COUNTER , *e.at(0))
    }
}

#[test]
#[should_panic(expected: 'Decreasing an empty counter')]
fn test_panic_decrease_counter() {
    let (counter, _ , _) = __deploy__(ZERO_COUNT);

    assert(counter.get_counter() == ZERO_COUNT, 'Invalid count');

    counter.decrease_counter();
}

#[test]
fn test_successful_decrease_counter() {
    let (counter, _ , _) = __deploy__(5);
    let count_1 = counter.get_counter();
    assert(count_1 == 5, 'Invalid count');

    //execute decrease txn
    counter.decrease_counter();

    let final_count = counter.get_counter();
    assert(final_count == count_1 - 1, 'Invalid decrease count');
}

#[test]
#[feature("safe_dispatcher")]
fn test_safe_panic_reset_counter_by_non_owner() {

    let (counter, _ , safe_dispatcher) = __deploy__(ZERO_COUNT);
    assert(counter.get_counter() == ZERO_COUNT, 'Invalid count');

    start_cheat_caller_address(counter.contract_address, USER_1());
    match safe_dispatcher.reset_counter() {
        Result::Ok(_) => panic!("only owner should be able to reset counter"),
        Result::Err(e) => assert(*e[0] == OwnableComponent::Errors::NOT_OWNER, *e.at(0))
    }
    stop_cheat_caller_address(counter.contract_address);
}


#[test]
fn test_successful_reset_counter() {
    let (counter, _ , _) = __deploy__(5);
    let count_1 = counter.get_counter();
    assert(count_1 == 5, 'Invalid count');   

    start_cheat_caller_address(counter.contract_address, OWNER());
    counter.reset_counter();
    stop_cheat_caller_address(counter.contract_address);

    let final_count = counter.get_counter();
    assert(final_count == ZERO_COUNT, 'Invalid reset count');

}

