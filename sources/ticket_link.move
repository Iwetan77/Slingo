#[allow(unused_use, unused_const)]
module slingoapp::ticket_link {
 
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::event;
    use std::string::{String};

    // Errors
    const EInvalidAmount: u64 = 0;
    const ELinkExpired: u64 = 1;
    const EInvalidSeller: u64 = 2;

    // Struct to represent the ticket link
    public struct TicketLink has key, store {
        id: UID,
        seller: address,
        price: u64,
        expiration: u64,
        event_name: String,
        max_tickets: u64,
        tickets_sold: u64,
        active: bool,
    }

    // Struct to represent the purchased ticket
    public struct Ticket has key {
        id: UID,
        link_id: ID,
        event_name: String,
        purchase_time: u64,
        owner: address,
    }

    // Event emitted when a ticket is purchased
    public struct TicketPurchased has copy, drop {
        ticket_id: ID,
        link_id: ID,
        buyer: address,
        price: u64,
        event_name: String,
    }

    // Create a new ticket link
    public fun create_ticket_link(
        seller: address,
        price: u64,
        expiration: u64,
        event_name: String,
        max_tickets: u64,
        ctx: &mut TxContext
    ) {
        let ticket_link = TicketLink {
            id: object::new(ctx),
            seller,
            price,
            expiration,
            event_name,
            max_tickets,
            tickets_sold: 0,
            active: true,
        };

        transfer::share_object(ticket_link);
    }

    // Getter for seller field
    public fun get_seller(link: &TicketLink): address {
        link.seller
    }

    public fun get_price(link: &TicketLink): u64 {
        link.price
    }

    public fun get_max_tickets(link: &TicketLink): u64 {
        link.max_tickets
    }

    public fun get_tickets_sold(link: &TicketLink): u64 {
        link.tickets_sold
    }

    public fun is_active(link: &TicketLink): bool {
        link.active
    }

    public fun get_event_name(link: &TicketLink): String {
        link.event_name
    }

    // Getter methods for Ticket
    public fun get_ticket_owner(ticket: &Ticket): address {
        ticket.owner
    }

    public fun get_ticket_event_name(ticket: &Ticket): String {
        ticket.event_name
    }



    // Purchase a ticket using the link
    public fun purchase_ticket(
        link: &mut TicketLink,
        payment: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        // Verify the link is still active and not expired
        assert!(link.active, ELinkExpired);
        assert!(tx_context::epoch(ctx) <= link.expiration, ELinkExpired);
        
        // Verify correct payment amount
        let payment_amount = coin::value(&payment);
        assert!(payment_amount == link.price, EInvalidAmount);

        // Verify tickets are still available
        assert!(link.tickets_sold < link.max_tickets, ELinkExpired);

        // Transfer payment to seller
        transfer::public_transfer(payment, link.seller);

        // Create new ticket
        let ticket = Ticket {
            id: object::new(ctx),
            link_id: object::id(link),
            event_name: link.event_name,
            purchase_time: tx_context::epoch(ctx),
            owner: tx_context::sender(ctx),
        };

        // Increment tickets sold
        link.tickets_sold = link.tickets_sold + 1;

        // Emit purchase event
        event::emit(TicketPurchased {
            ticket_id: object::id(&ticket),
            link_id: object::id(link),
            buyer: tx_context::sender(ctx),
            price: link.price,
            event_name: link.event_name,
        });

        // Transfer ticket to buyer
        transfer::transfer(ticket, tx_context::sender(ctx));
    }

    // Deactivate a ticket link (only seller can do this)
    public fun deactivate_link(
        link: &mut TicketLink,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == link.seller, EInvalidSeller);
        link.active = false;
    }


    #[test_only]
    use sui::test_scenario;
    use std::string;
    use slingoapp::ticket_link::{Self, };

    // Constants for testing
    const SELLER: address = @0xA1;
    const BUYER: address = @0xB1;
    const TICKET_PRICE: u64 = 100;
    const MAX_TICKETS: u64 = 10;

    #[test]
    fun test_create_ticket_link() {
        let mut scenario = test_scenario::begin(SELLER);
        
        // Create ticket link
        test_scenario::next_tx(&mut scenario, SELLER);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            ticket_link::create_ticket_link(
                SELLER,
                TICKET_PRICE,
                100, // expiration epoch
                string::utf8(b"Test Event"),
                MAX_TICKETS,
                ctx
            );
        };
        
        // Verify ticket link
        test_scenario::next_tx(&mut scenario, SELLER);
        {
            let link = test_scenario::take_shared<TicketLink>(&scenario);
            
            assert!(ticket_link::get_seller(&link) == SELLER, 0);
            assert!(ticket_link::get_price(&link) == TICKET_PRICE, 1);
            assert!(ticket_link::get_max_tickets(&link) == MAX_TICKETS, 2);
            assert!(ticket_link::get_tickets_sold(&link) == 0, 3);
            assert!(ticket_link::is_active(&link) == true, 4);
            assert!(ticket_link::get_event_name(&link) == string::utf8(b"Test Event"), 5);
            
            test_scenario::return_shared(link);
        };
        
        test_scenario::end(scenario);
    }

    #[test]
    fun test_purchase_ticket() {
        let mut scenario = test_scenario::begin(SELLER);
        
        // Create ticket link
        test_scenario::next_tx(&mut scenario, SELLER);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            ticket_link::create_ticket_link(
                SELLER,
                TICKET_PRICE,
                100,
                string::utf8(b"Test Event"),
                MAX_TICKETS,
                ctx
            );
        };
        
        // Purchase ticket
        test_scenario::next_tx(&mut scenario, BUYER);
        {
            let mut link = test_scenario::take_shared<TicketLink>(&scenario);
            let coin = coin::mint_for_testing<SUI>(TICKET_PRICE, test_scenario::ctx(&mut scenario));
            
            ticket_link::purchase_ticket(&mut link, coin, test_scenario::ctx(&mut scenario));
            
            // Verify ticket link state
            assert!(ticket_link::get_tickets_sold(&link) == 1, 6);
            test_scenario::return_shared(link);
        };
        
        // Verify buyer received ticket
        test_scenario::next_tx(&mut scenario, BUYER);
        {
            let ticket = test_scenario::take_from_address<Ticket>(&scenario, BUYER);
            
            assert!(ticket_link::get_ticket_owner(&ticket) == BUYER, 7);
            assert!(ticket_link::get_ticket_event_name(&ticket) == string::utf8(b"Test Event"), 8);
            
            test_scenario::return_to_address(BUYER, ticket);
        };
        
        test_scenario::end(scenario);
    }

    // Additional test cases
    #[test]
    #[expected_failure(abort_code = 1, location = Self)]
    fun test_exceed_max_tickets() {
        let mut scenario = test_scenario::begin(SELLER);
        
        // Create ticket link
        test_scenario::next_tx(&mut scenario, SELLER);
        {
            let ctx = test_scenario::ctx(&mut scenario);
            ticket_link::create_ticket_link(
                SELLER,
                TICKET_PRICE,
                100,
                string::utf8(b"Test Event"),
                1, // Only 1 ticket allowed
                ctx
            );
        };
        
        // Purchase first ticket
        test_scenario::next_tx(&mut scenario, @0xC1);
        {
            let mut link = test_scenario::take_shared<TicketLink>(&scenario);
            let coin = coin::mint_for_testing<SUI>(TICKET_PRICE, test_scenario::ctx(&mut scenario));
            
            ticket_link::purchase_ticket(&mut link, coin, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(link);
        };
        
        // Attempt to purchase second ticket (should fail)
        test_scenario::next_tx(&mut scenario, @0xD1);
        {
            let mut link = test_scenario::take_shared<TicketLink>(&scenario);
            let coin = coin::mint_for_testing<SUI>(TICKET_PRICE, test_scenario::ctx(&mut scenario));
            
            ticket_link::purchase_ticket(&mut link, coin, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(link);
        };
        
        test_scenario::end(scenario);
    }
}
