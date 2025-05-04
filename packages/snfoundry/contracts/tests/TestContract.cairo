use contracts::Counter::Counter::FELT_STRK_CONTRACT;
use contracts::Counter::{
    Counter, ICounterDispatcher, ICounterDispatcherTrait, ICounterSafeDispatcher,
    ICounterSafeDispatcherTrait,
};
use openzeppelin_access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::ContractAddress;


const ZERO_COUNT: u32 = 0;
const STRK_AMOUNT: u256 = 5000000000000000000; // 5 STRK (18 decimals)

fn OWNER() -> ContractAddress {
    'OWNER'.try_into().unwrap()
}

fn USER_1() -> ContractAddress {
    'USER_1'.try_into().unwrap()
}

fn STRK() -> ContractAddress {
    FELT_STRK_CONTRACT.try_into().unwrap()
}

pub const SOME_STRK_TOKEN_HOLDER_ADDRESS: felt252 =
    0x04840eaf28b606a8c3dca29e3b554a299a2d566a55acc1265046500f90ee525c;

fn STRK_TOKEN_HOLDER() -> ContractAddress {
    SOME_STRK_TOKEN_HOLDER_ADDRESS.try_into().unwrap()
}


//util deploy function

fn __deploy__(
    init_value: u32,
) -> (ICounterDispatcher, IOwnableDispatcher, ICounterSafeDispatcher, IERC20Dispatcher) {
    let contractClass = declare("Counter").unwrap().contract_class();

    //serialize calldata
    let mut calldata: Array<felt252> = array![];

    OWNER().serialize(ref calldata);
    init_value.serialize(ref calldata);

    //deploy contract
    let (contract_address, _) = contractClass.deploy(@calldata).expect('Deploy failed');

    let counter = ICounterDispatcher { contract_address };
    let ownable = IOwnableDispatcher { contract_address };
    let safe_dispatcher = ICounterSafeDispatcher { contract_address };
    let strk_token = IERC20Dispatcher { contract_address: STRK() };

    //smiulating transfer STRK to contract
    transfer_strk(STRK_TOKEN_HOLDER(), contract_address, STRK_AMOUNT);

    (counter, ownable, safe_dispatcher, strk_token)
}

fn get_strk_token_balance(account: ContractAddress) -> u256 {
    IERC20Dispatcher { contract_address: STRK() }.balance_of(account)
}

fn transfer_strk(caller: ContractAddress, recipient: ContractAddress, amount: u256) {
    start_cheat_caller_address(STRK(), caller);
    let token_dispatcher = IERC20Dispatcher { contract_address: STRK() };
    token_dispatcher.transfer(recipient, amount);
    stop_cheat_caller_address(STRK());
}

fn aprove_strk(owner: ContractAddress, spender: ContractAddress, amount: u256) {
    start_cheat_caller_address(STRK(), owner);
    let token_dispatcher = IERC20Dispatcher { contract_address: STRK() };
    token_dispatcher.approve(spender, amount);
    stop_cheat_caller_address(STRK());
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_counter_deployment() {
    let (counter, ownable, _, _) = __deploy__(0);

    //count 1
    let count_1 = counter.get_counter();

    assert(count_1 == ZERO_COUNT, 'Counter should be 0');
    assert(ownable.owner() == OWNER(), 'Owner not set');
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_increase_counter() {
    let (counter, _, _, _) = __deploy__(ZERO_COUNT);

    let count_1 = counter.get_counter();

    assert(count_1 == ZERO_COUNT, 'Counter should be 0');

    //increase counter
    counter.increase_counter();

    let count_2 = counter.get_counter();
    assert(count_2 == count_1 + 1, 'Invalid count');
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_emitted_increased_event() {
    let (counter, _, _, _) = __deploy__(ZERO_COUNT);
    let mut spy = spy_events();

    //mock a caller
    start_cheat_caller_address(counter.contract_address, USER_1());
    counter.increase_counter();
    stop_cheat_caller_address(counter.contract_address);
    spy
        .assert_emitted(
            @array![
                (
                    counter.contract_address,
                    Counter::Event::Increased(Counter::Increased { account: USER_1() }),
                ),
            ],
        );

    spy
        .assert_not_emitted(
            @array![
                (
                    counter.contract_address,
                    Counter::Event::Decreased(Counter::Decreased { account: USER_1() }),
                ),
            ],
        )
    //test win condition

}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_increase_counter_contract_transfers_strk_to_caller_when_count_is_win_number() {
    let (counter, _, _, _) = __deploy__(Counter::WIN_NUMBER - 1);

    let count_1 = counter.get_counter();
    assert(count_1 == Counter::WIN_NUMBER - 1, 'Invalid count');

    let counter_strk_balance_1 = get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance_1 == STRK_AMOUNT, 'Invalid STRK balance');

    let user1_strk_balance_1 = get_strk_token_balance(USER_1());
    assert(user1_strk_balance_1 == 0, 'Invalid USER_1 STRK balance');

    //simulating txn increase_counter coming from USER_1
    start_cheat_caller_address(counter.contract_address, USER_1());

    //simulating tsx to transfer STRK token initiated by the counter contract
    // start_cheat_caller_address(STRK(), counter.contract_address);

    let win_number = counter.get_win_number();
    assert(win_number == Counter::WIN_NUMBER, 'Invalid win number');

    //increase counter by USER_1
    counter.increase_counter();
    stop_cheat_caller_address(counter.contract_address);

    let count_2 = counter.get_counter();
    assert(count_2 == count_1 + 1, 'Invalid count');

    //check if all STRK tokens are transferred
    let counter_strk_balance_2 = get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance_2 == 0, 'Invalid counter_2 STRK balance');

    //check if USER_1 received STRK tokens
    let user_1_strk_balance_2 = get_strk_token_balance(USER_1());
    assert(user_1_strk_balance_2 == STRK_AMOUNT, 'STRK tokens was not transferred');
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_increase_counter_does_not_transfer_strk_token_to_caller_when_counter_contract_has_zero_strk() {
    let test_count: u32 = 9;
    let (counter, _, _, _) = __deploy__(test_count);

    let count_1 = counter.get_counter();
    assert(count_1 == test_count, 'Counter should be 0');

    let counter_strk_balance_1 = get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance_1 == STRK_AMOUNT, 'Invalid STRK balance');

    //check USER_1 has no STRK tokens
    let user_1_strk_balance_1 = get_strk_token_balance(USER_1());
    assert(user_1_strk_balance_1 == 0, 'Invalid USER_1 STRK balance');

    //transfer all STRK tokens to the counter contract
    transfer_strk(counter.contract_address, OWNER(), STRK_AMOUNT);

    //validate that transfer was successful from counter to owner
    let counter_strk_balance_2 = get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance_2 == 0, 'Invalid counter STRK balance');

    let owner_strk_balance_2 = get_strk_token_balance(OWNER());
    assert(owner_strk_balance_2 == STRK_AMOUNT, 'Invalid owner STRK balance');

    //simulate txn increase_counter coming from USER_1
    start_cheat_caller_address(counter.contract_address, USER_1());
    let win_number = counter.get_win_number();
    assert(win_number == Counter::WIN_NUMBER, 'Invalid win number');

    //increase counter by USER_1
    counter.increase_counter();
    stop_cheat_caller_address(counter.contract_address);

    let count_2 = counter.get_counter();
    assert(count_2 == count_1 + 1, 'Invalid count');
    assert(count_2 == Counter::WIN_NUMBER, 'Counter should be win number');

    //check that no STRK tokens are transferred to USER_1
    let user_1_strk_balance_2 = get_strk_token_balance(USER_1());
    assert(user_1_strk_balance_2 == 0, 'Invalid USER_1 STRK balance');

    //validate that counter contract remains with 0 STRK balance
    let counter_strk_balance_2 = get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance_2 == 0, 'Invalid counter STRK balance');
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
#[feature("safe_dispatcher")]
fn test_safe_panic_decrease_counter() {
    let (counter, _, safe_dispatcher, _) = __deploy__(ZERO_COUNT);
    assert(counter.get_counter() == ZERO_COUNT, 'Invalid count');

    match safe_dispatcher.decrease_counter() {
        Result::Ok(_) => panic!("cannot decrease 0"),
        Result::Err(e) => assert(*e[0] == Counter::Error::EMPTY_COUNTER, *e.at(0)),
    }
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
#[should_panic(expected: 'Decreasing Empty counter')]
fn test_panic_decrease_counter() {
    let (counter, _, _, _) = __deploy__(ZERO_COUNT);

    assert(counter.get_counter() == ZERO_COUNT, 'Invalid count');

    counter.decrease_counter();
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_emitted_decreased_event() {
    let (counter, _, _, _) = __deploy__(1);
    let mut spy = spy_events();

    //mock a caller
    start_cheat_caller_address(counter.contract_address, USER_1());
    counter.decrease_counter();
    stop_cheat_caller_address(counter.contract_address);
    spy
        .assert_emitted(
            @array![
                (
                    counter.contract_address,
                    Counter::Event::Decreased(Counter::Decreased { account: USER_1() }),
                ),
            ],
        );

    spy
        .assert_not_emitted(
            @array![
                (
                    counter.contract_address,
                    Counter::Event::Increased(Counter::Increased { account: USER_1() }),
                ),
            ],
        )
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_successful_decrease_counter() {
    let (counter, _, _, _) = __deploy__(5);
    let count_1 = counter.get_counter();
    assert(count_1 == 5, 'Invalid count');

    //execute decrease txn
    counter.decrease_counter();

    let final_count = counter.get_counter();
    assert(final_count == count_1 - 1, 'Invalid decrease count');
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_successful_reset_counter() {
    let test_count: u32 = 5;
    let (counter, _, _, strk_token) = __deploy__(test_count);

    //Create a spy instance to track events
    let mut spy = spy_events();

    let test_strk_amount: u256 = 10000000000000000000; // 10 STRK

    let count_1 = counter.get_counter();
    assert(count_1 == test_count, 'Invalid count');

    //Approve STRK transfer from USER_1 to enable counter contract to spend STRK
    aprove_strk(USER_1(), counter.contract_address, test_strk_amount);

    let counter_allowance = strk_token.allowance(USER_1(), counter.contract_address);
    assert(counter_allowance == test_strk_amount, 'Invalid allowance');

    let strk_holder_balance = get_strk_token_balance(STRK_TOKEN_HOLDER());
    assert(strk_holder_balance > test_strk_amount, 'Insuficient STRK balance');

    //transfer STRK from provider to USER_1 who is executin the txn
    transfer_strk(STRK_TOKEN_HOLDER(), USER_1(), test_strk_amount);

    //validate txn
    let user_1_strk_balance_1 = get_strk_token_balance(USER_1());
    assert(user_1_strk_balance_1 == test_strk_amount, 'Invalid USER_1 STRK balance');

    //check that counter contract has sufficient balance to pay
    let counter_strk_balance = get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance == STRK_AMOUNT, 'Invalid counter STRK balance');

    //simulate txn to reset counter
    start_cheat_caller_address(counter.contract_address, USER_1());

    counter.reset_counter();
    stop_cheat_caller_address(counter.contract_address);

    let count_2 = counter.get_counter();
    assert(count_2 == ZERO_COUNT, 'counter not reseted');

    //validate that counter contract has received STRK tokens sent by USER_1
    let counter_strk_balance_2 = get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance_2 == 2 * counter_strk_balance, 'no strk transferred to counter');

    //validate that USER_1 balance was reduced by the amount of STRK tokens sent
    let user_1_strk_balance_2 = get_strk_token_balance(USER_1());
    assert(user_1_strk_balance_2 == test_strk_amount - STRK_AMOUNT, 'caller balance not reduced');

    spy
        .assert_emitted(
            @array![
                (
                    counter.contract_address,
                    Counter::Event::Reset(Counter::Reset { account: USER_1() }),
                ),
            ],
        );

    spy
        .assert_not_emitted(
            @array![
                (
                    counter.contract_address,
                    Counter::Event::Increased(Counter::Increased { account: USER_1() }),
                ),
                (
                    counter.contract_address,
                    Counter::Event::Decreased(Counter::Decreased { account: USER_1() }),
                ),
            ],
        );
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_reset_counter_when_counter_contract_strk_balance_is_zero() {
    const test_count: u32 = Counter::WIN_NUMBER - 1;
    let (counter, _, _, _) = __deploy__(test_count);
    let count_1 = counter.get_counter();
    assert(count_1 == test_count, 'Invalid count');

    let counter_strk_balance = get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance == STRK_AMOUNT, 'Invalid counter STRK balance');

    let user_1_strk_balance = get_strk_token_balance(USER_1());
    assert(user_1_strk_balance == 0, 'Invalid USER_1 STRK balance');

    //simulate txn icrease_counter call coming from USER_1
    start_cheat_caller_address(counter.contract_address, USER_1());

    let win_number = counter.get_win_number();
    assert(win_number == Counter::WIN_NUMBER, 'Invalid win number');

    //increase counter by USER_1
    counter.increase_counter();
    stop_cheat_caller_address(counter.contract_address);

    let count_2 = counter.get_counter();
    assert(count_2 == count_1 + 1, 'Invalid count');

    // check if all STRK tokens are transferred to the counter contract
    let counter_strk_balance_2 = get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance_2 == 0, 'Invalid counter STRK balance');

    // check if USER_1 balance was reduced by the amount of STRK tokens sent
    let user_1_strk_balance_2 = get_strk_token_balance(USER_1());
    assert(user_1_strk_balance_2 == STRK_AMOUNT, 'Invalid USER_1 STRK balance');

    //simulate txn reset_counter call coming from USER_1
    start_cheat_caller_address(counter.contract_address, USER_1());
    counter.reset_counter();
    stop_cheat_caller_address(counter.contract_address);

    let count_3 = counter.get_counter();
    assert(count_3 == ZERO_COUNT, 'counter not reseted');

    //validate that balance is not changed during reset
    let counter_strk_balance_3 = get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance_3 == counter_strk_balance_2, 'Invalid counter STRK balance');

    let user_1_strk_balance_3 = get_strk_token_balance(USER_1());
    assert(user_1_strk_balance_3 == user_1_strk_balance_2, 'Invalid USER_1 STRK balance');
}

#[test]
#[fork("MAINNET_LATEST", block_tag: latest)]
fn test_reset_counter_contract_receives_no_strk_token_when_strk_balance_is_zero() {
    let mut spy = spy_events();

    let (counter, _, _, _) = __deploy__(Counter::WIN_NUMBER - 1);
    let count_1 = counter.get_counter();
    assert(count_1 == Counter::WIN_NUMBER - 1, 'Invalid count');

    let counter_strk_balance_1 = get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance_1 == STRK_AMOUNT, 'Invalid counter STRK balance');
    
    let user_1_strk_balance_1 = get_strk_token_balance(USER_1());
    assert(user_1_strk_balance_1 == 0, 'Invalid USER_1 STRK balance');

    //simulate txn increase_counter call coming from USER_1
    start_cheat_caller_address(counter.contract_address, USER_1());

    let win_number = counter.get_win_number();
    assert(win_number == Counter::WIN_NUMBER, 'Invalid win number');

    //increase counter by USER_1
    counter.increase_counter();
    stop_cheat_caller_address(counter.contract_address);

    let count_2 = counter.get_counter();
    assert(count_2 == count_1 + 1, 'Invalid count');

    //check if all STRK tokens are transferred to the USER_1 from the counter contract
    let counter_strk_balance_2 = get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance_2 == 0, 'Invalid counter STRK balance');

    //check if USER_1 balance was increased by the amount of STRK tokens sent
    let user_1_strk_balance_2 = get_strk_token_balance(USER_1());
    assert(user_1_strk_balance_2 == STRK_AMOUNT, 'Invalid USER_1 STRK balance');

    //simulate txn reset_counter call coming from USER_1
    start_cheat_caller_address(counter.contract_address, USER_1());
    counter.reset_counter();
    stop_cheat_caller_address(counter.contract_address);

    let count_3 = counter.get_counter();
    assert(count_3 == ZERO_COUNT, 'counter not reseted');

    //check if counter contract has received no STRK tokens
    let counter_strk_balance_3 = get_strk_token_balance(counter.contract_address);
    assert(counter_strk_balance_3 == 0, 'Invalid counter STRK balance');
    
    //uer_1 balance is not changed
    let user_1_strk_balance_3 = get_strk_token_balance(USER_1());
    assert(user_1_strk_balance_3 == user_1_strk_balance_2, 'Invalid USER_1 STRK balance');
    
    spy.assert_emitted(
        @array![
            (
                counter.contract_address,
                Counter::Event::Reset(Counter::Reset { account: USER_1() }),
            ),
        ],
    );

}