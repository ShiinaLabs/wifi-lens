use wifi_lens_core::mac_vendor::{
    lookup_mac_vendor, lookup_mac_vendor_organization, parse_mac_vendor_database,
    wifi_lens_mac_vendor_parse_database, MacVendorEntry, MacVendorError, MacVendorLookup,
    MacVendorRegistry, MacVendorRegistryInput, WiFiLensMacVendorEntry, WiFiLensMacVendorFailure,
    WiFiLensMacVendorMinimum, WiFiLensMacVendorRegistryInput, WiFiLensMacVendorRegistryMetadata,
};

#[test]
fn parse_ffi_preserves_error_code_and_reports_required_detail_capacity() {
    let name = "x".repeat(600);
    let csvs = [
        b"Registry,Assignment,Organization Name\nMA-L,invalid,Example\n".as_slice(),
        b"Registry,Assignment,Organization Name\nMA-M,0011223,Example\n",
        b"Registry,Assignment,Organization Name\nMA-S,001122334,Example\n",
        b"Registry,Assignment,Organization Name\nIAB,001122335,Example\n",
    ];
    let mut strings = Vec::new();
    let mut inputs = Vec::new();
    for csv in csvs {
        let display_name_offset = strings.len();
        strings.extend_from_slice(name.as_bytes());
        let data_offset = strings.len();
        strings.extend_from_slice(csv);
        inputs.push(WiFiLensMacVendorRegistryInput {
            display_name_offset,
            display_name_length: name.len(),
            data_offset,
            data_length: csv.len(),
        });
    }
    let minimums = [1, 2, 3, 4].map(|registry| WiFiLensMacVendorMinimum {
        registry,
        minimum_records: 1,
    });
    let mut failure = WiFiLensMacVendorFailure::default();
    let mut failure_text = vec![0u8; 1];
    let mut failure_text_length = 0;
    let mut registries = [WiFiLensMacVendorRegistryMetadata::default(); 4];
    let mut entries = [WiFiLensMacVendorEntry::default(); 1];
    let mut text = [0u8; 0];
    let (mut registries_count, mut entries_count, mut text_length) = (0, 0, 0);

    let status = unsafe {
        wifi_lens_mac_vendor_parse_database(
            inputs.as_ptr(),
            inputs.len(),
            strings.as_ptr(),
            strings.len(),
            2,
            minimums.as_ptr(),
            minimums.len(),
            4096,
            4096,
            None,
            std::ptr::null_mut(),
            &mut failure,
            failure_text.as_mut_ptr(),
            failure_text.len(),
            &mut failure_text_length,
            registries.as_mut_ptr(),
            registries.len(),
            entries.as_mut_ptr(),
            entries.len(),
            text.as_mut_ptr(),
            0,
            &mut registries_count,
            &mut entries_count,
            &mut text_length,
        )
    };
    assert_eq!(status, 14);
    assert_eq!(failure.code, 10);
    assert_eq!(failure_text_length, name.len() + b"invalid".len());

    failure_text.resize(failure_text_length, 0);
    let retry_status = unsafe {
        wifi_lens_mac_vendor_parse_database(
            inputs.as_ptr(),
            inputs.len(),
            strings.as_ptr(),
            strings.len(),
            2,
            minimums.as_ptr(),
            minimums.len(),
            4096,
            4096,
            None,
            std::ptr::null_mut(),
            &mut failure,
            failure_text.as_mut_ptr(),
            failure_text.len(),
            &mut failure_text_length,
            registries.as_mut_ptr(),
            registries.len(),
            entries.as_mut_ptr(),
            entries.len(),
            text.as_mut_ptr(),
            0,
            &mut registries_count,
            &mut entries_count,
            &mut text_length,
        )
    };
    assert_eq!(retry_status, 14);
    assert_eq!(failure.code, 10);
    assert_eq!(failure_text_length, name.len() + b"invalid".len());
    assert_eq!(&failure_text[name.len()..], b"invalid");
}

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
    assert_eq!(case_count, 12);
}
