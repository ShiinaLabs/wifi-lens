use wifi_lens_core::mac_vendor::{
    lookup_mac_vendor, lookup_mac_vendor_organization, parse_mac_vendor_database, MacVendorEntry,
    MacVendorError, MacVendorLookup, MacVendorRegistry, MacVendorRegistryInput,
};

#[test]
fn parser_preserves_format_stripping_assignment_normalization_sha256_and_order() {
    let mut owned = Vec::new();
    let assignment = "00:11:aa";
    let csv = format!(
        "\u{feff}Registry,Assignment,Organization Name\r\nMA-L,{assignment},\"\u{200b}Example, Inc.\"\r\n"
    );
    owned.push(csv);
    for registry in [
        MacVendorRegistry::MaM,
        MacVendorRegistry::MaS,
        MacVendorRegistry::Iab,
    ] {
        owned.push(format!(
            "Registry,Assignment,Organization Name\n{},{},Example\n",
            registry.raw_name(),
            match registry {
                MacVendorRegistry::MaM => "0011223",
                MacVendorRegistry::MaS => "001122334",
                MacVendorRegistry::Iab => "001122335",
                MacVendorRegistry::MaL => unreachable!(),
            }
        ));
    }
    let inputs: Vec<_> = owned
        .iter()
        .map(|csv| MacVendorRegistryInput {
            display_name: "fixture.csv",
            data: csv.as_bytes(),
        })
        .collect();
    let minimums = MacVendorRegistry::ALL
        .into_iter()
        .map(|registry| (registry, 1usize))
        .collect::<Vec<_>>();
    let database = parse_mac_vendor_database(
        &inputs,
        &minimums,
        16 * 1024 * 1024,
        32 * 1024 * 1024,
        |_| Ok::<_, MacVendorError>(()),
    )
    .unwrap();

    let masked = database
        .entries
        .iter()
        .find(|entry| entry.prefix == "0011AA" && entry.prefix_length_bits == 24)
        .unwrap();
    assert_eq!(masked.organization, "Example, Inc.");
    assert_eq!(
        database.registries[0].sha256,
        "8de45210f0c385748e2042a96f02da50ef80a63e6a41ff1388a12ff4d80ef96d"
    );
    assert_eq!(database.entries[0].prefix_length_bits, 36);
    assert_eq!(database.entries[1].prefix_length_bits, 36);
    assert_eq!(database.entries[2].prefix_length_bits, 28);
    assert_eq!(database.entries[3].prefix_length_bits, 24);
    assert_eq!(
        lookup_mac_vendor_organization("00:11:AA:33:44:55", &database.entries).as_deref(),
        Some("Example, Inc.")
    );
}

#[test]
fn shared_lookup_fixtures_match_typed_api() {
    let mut case_count = 0;
    for line in include_str!("fixtures/mac-vendor-cases.tsv").lines() {
        if line.trim().is_empty() || line.starts_with('#') {
            continue;
        }
        let fields: Vec<_> = line.split('\t').collect();
        assert_eq!(fields.len(), 8, "invalid fixture {}", fields[1]);
        assert_eq!(fields[0], "lookup", "unsupported fixture {}", fields[1]);
        let mut entries = vec![MacVendorEntry {
            prefix: fields[3].to_string(),
            prefix_length_bits: fields[4].parse().unwrap(),
            organization: fields[5].to_string(),
        }];
        if fields[1] == "longest-prefix-36" {
            entries.push(MacVendorEntry {
                prefix: "001122".to_string(),
                prefix_length_bits: 24,
                organization: "Large Networks".to_string(),
            });
        }
        let expected_code: i32 = fields[6].parse().unwrap();
        let expected_state = match expected_code {
            0 => MacVendorLookup::Invalid,
            1 => MacVendorLookup::Unknown,
            2 => MacVendorLookup::LocallyAdministered,
            3 => MacVendorLookup::Registered,
            value => panic!("invalid expected state {value}"),
        };
        assert_eq!(
            lookup_mac_vendor(fields[2], &entries),
            expected_state,
            "fixture {}",
            fields[1]
        );
        let expected_organization = if fields[7] == "-" {
            None
        } else {
            Some(fields[7])
        };
        assert_eq!(
            lookup_mac_vendor_organization(fields[2], &entries).as_deref(),
            expected_organization,
            "organization fixture {}",
            fields[1]
        );
        case_count += 1;
    }
    assert_eq!(case_count, 10);
}
