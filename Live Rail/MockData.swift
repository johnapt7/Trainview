import Foundation

enum MockData {

    static let stations: [Station] = [
        Station(code: "KGX", name: "King's Cross", dist: 0.8),
        Station(code: "STP", name: "St Pancras Intl", dist: 0.9),
        Station(code: "EUS", name: "Euston", dist: 1.4),
        Station(code: "PAD", name: "Paddington", dist: 3.2),
        Station(code: "VIC", name: "Victoria", dist: 4.1),
        Station(code: "WAT", name: "Waterloo", dist: 4.6),
        Station(code: "LST", name: "Liverpool Street", dist: 2.1),
    ]

    static let departures: [Train] = [
        Train(
            id: "t001", time: "14:02", destination: "Edinburgh Waverley", origin: "London King's Cross",
            via: "York \u{00B7} Newcastle \u{00B7} Berwick", platform: "3",
            operator: "Northbound Rail", operatorCode: "NBR",
            status: .onTime, statusNote: "On time", type: "IC-225", carriages: 9, duration: "4h 19m",
            stops: [
                Stop(station: "London King's Cross", time: "14:02", platform: "3", type: .origin),
                Stop(station: "Stevenage", time: "14:27", platform: "2", type: .stop),
                Stop(station: "Peterborough", time: "14:48", platform: "4", type: .stop),
                Stop(station: "Grantham", time: "15:12", platform: "1", type: .stop),
                Stop(station: "Newark North Gate", time: "15:31", platform: "2", type: .stop),
                Stop(station: "Doncaster", time: "15:54", platform: "3B", type: .stop),
                Stop(station: "York", time: "16:14", platform: "9", type: .major),
                Stop(station: "Darlington", time: "16:44", platform: "1", type: .stop),
                Stop(station: "Durham", time: "17:02", platform: "2", type: .stop),
                Stop(station: "Newcastle", time: "17:18", platform: "3", type: .major),
                Stop(station: "Berwick-upon-Tweed", time: "18:00", platform: "1", type: .stop),
                Stop(station: "Edinburgh Waverley", time: "18:21", platform: "7", type: .destination),
            ]
        ),
        Train(
            id: "t002", time: "14:08", destination: "Penzance", origin: "London Paddington",
            via: "Reading \u{00B7} Exeter \u{00B7} Plymouth", platform: "7",
            operator: "Westline Express", operatorCode: "WLX",
            status: .delayed, statusNote: "+6 min", type: "IET-802", carriages: 10, duration: "5h 03m",
            stops: [
                Stop(station: "London Paddington", time: "14:08", platform: "7", type: .origin),
                Stop(station: "Reading", time: "14:33", platform: "5", type: .stop),
                Stop(station: "Taunton", time: "15:42", platform: "2", type: .stop),
                Stop(station: "Exeter St Davids", time: "16:12", platform: "4", type: .major),
                Stop(station: "Plymouth", time: "17:18", platform: "6", type: .major),
                Stop(station: "Liskeard", time: "17:42", platform: "1", type: .stop),
                Stop(station: "Bodmin Parkway", time: "17:54", platform: "2", type: .stop),
                Stop(station: "Par", time: "18:08", platform: "1", type: .stop),
                Stop(station: "St Austell", time: "18:18", platform: "2", type: .stop),
                Stop(station: "Truro", time: "18:42", platform: "1", type: .stop),
                Stop(station: "Redruth", time: "18:54", platform: "2", type: .stop),
                Stop(station: "St Erth", time: "19:03", platform: "1", type: .stop),
                Stop(station: "Penzance", time: "19:11", platform: "3", type: .destination),
            ]
        ),
        Train(
            id: "t003", time: "14:15", destination: "Paris Gare du Nord", origin: "London St Pancras Intl",
            via: "Ashford Intl \u{00B7} Lille Europe", platform: "5",
            operator: "Continental Link", operatorCode: "CNL",
            status: .onTime, statusNote: "Boarding", type: "TMS-373", carriages: 16, duration: "2h 22m",
            stops: [
                Stop(station: "London St Pancras Intl", time: "14:15", platform: "5", type: .origin),
                Stop(station: "Ebbsfleet Intl", time: "14:35", platform: "2", type: .stop),
                Stop(station: "Ashford Intl", time: "14:52", platform: "1", type: .stop),
                Stop(station: "Lille Europe", time: "16:22", platform: "3", type: .major),
                Stop(station: "Paris Gare du Nord", time: "16:37", platform: "7", type: .destination),
            ]
        ),
        Train(
            id: "t004", time: "14:22", destination: "Manchester Piccadilly", origin: "London Euston",
            via: "Milton Keynes \u{00B7} Stoke-on-Trent", platform: "12",
            operator: "Avanti North", operatorCode: "AVN",
            status: .onTime, statusNote: "On time", type: "C390-P", carriages: 11, duration: "2h 08m",
            stops: [
                Stop(station: "London Euston", time: "14:22", platform: "12", type: .origin),
                Stop(station: "Milton Keynes Central", time: "14:53", platform: "3", type: .stop),
                Stop(station: "Stoke-on-Trent", time: "15:46", platform: "2", type: .major),
                Stop(station: "Macclesfield", time: "16:04", platform: "1", type: .stop),
                Stop(station: "Stockport", time: "16:19", platform: "3", type: .stop),
                Stop(station: "Manchester Piccadilly", time: "16:30", platform: "5", type: .destination),
            ]
        ),
        Train(
            id: "t005", time: "14:28", destination: "Brighton", origin: "London Victoria",
            via: "East Croydon \u{00B7} Gatwick Airport", platform: "14",
            operator: "Southern Coast", operatorCode: "SCR",
            status: .onTime, statusNote: "On time", type: "Cl.377", carriages: 8, duration: "1h 02m",
            stops: [
                Stop(station: "London Victoria", time: "14:28", platform: "14", type: .origin),
                Stop(station: "Clapham Junction", time: "14:35", platform: "13", type: .stop),
                Stop(station: "East Croydon", time: "14:43", platform: "5", type: .stop),
                Stop(station: "Gatwick Airport", time: "15:01", platform: "2", type: .major),
                Stop(station: "Three Bridges", time: "15:08", platform: "4", type: .stop),
                Stop(station: "Haywards Heath", time: "15:18", platform: "2", type: .stop),
                Stop(station: "Preston Park", time: "15:27", platform: "1", type: .stop),
                Stop(station: "Brighton", time: "15:30", platform: "3", type: .destination),
            ]
        ),
        Train(
            id: "t006", time: "14:35", destination: "Cardiff Central", origin: "London Paddington",
            via: "Reading \u{00B7} Swindon \u{00B7} Bristol Parkway", platform: "9",
            operator: "Westline Express", operatorCode: "WLX",
            status: .cancelled, statusNote: "Cancelled", type: "IET-800", carriages: 9, duration: "1h 56m",
            stops: [
                Stop(station: "London Paddington", time: "14:35", platform: "9", type: .origin),
                Stop(station: "Reading", time: "14:59", platform: "4", type: .stop),
                Stop(station: "Swindon", time: "15:24", platform: "3", type: .stop),
                Stop(station: "Bristol Parkway", time: "15:47", platform: "2", type: .major),
                Stop(station: "Newport", time: "16:14", platform: "3", type: .stop),
                Stop(station: "Cardiff Central", time: "16:31", platform: "4", type: .destination),
            ]
        ),
        Train(
            id: "t007", time: "14:44", destination: "Norwich", origin: "London Liverpool St",
            via: "Stratford \u{00B7} Colchester \u{00B7} Ipswich", platform: "6",
            operator: "Greater Anglia", operatorCode: "GRA",
            status: .onTime, statusNote: "On time", type: "Cl.745", carriages: 12, duration: "1h 52m",
            stops: [
                Stop(station: "London Liverpool St", time: "14:44", platform: "6", type: .origin),
                Stop(station: "Stratford", time: "14:50", platform: "10", type: .stop),
                Stop(station: "Chelmsford", time: "15:14", platform: "3", type: .stop),
                Stop(station: "Colchester", time: "15:33", platform: "2", type: .stop),
                Stop(station: "Ipswich", time: "15:59", platform: "4", type: .major),
                Stop(station: "Stowmarket", time: "16:14", platform: "1", type: .stop),
                Stop(station: "Diss", time: "16:24", platform: "2", type: .stop),
                Stop(station: "Norwich", time: "16:36", platform: "3", type: .destination),
            ]
        ),
    ]

    static let arrivals: [Train] = [
        Train(
            id: "a001", time: "14:03", destination: "London King's Cross", origin: "Leeds",
            via: "Wakefield \u{00B7} Doncaster \u{00B7} Peterborough", platform: "4",
            operator: "Northbound Rail", operatorCode: "NBR",
            status: .onTime, statusNote: "Arriving", type: "IC-225", carriages: 9, duration: "2h 14m",
            stops: [
                Stop(station: "Leeds", time: "11:49", platform: "12", type: .origin),
                Stop(station: "Wakefield Westgate", time: "12:04", platform: "2", type: .stop),
                Stop(station: "Doncaster", time: "12:24", platform: "3B", type: .stop),
                Stop(station: "Newark North Gate", time: "12:48", platform: "1", type: .stop),
                Stop(station: "Grantham", time: "13:06", platform: "2", type: .stop),
                Stop(station: "Peterborough", time: "13:26", platform: "5", type: .stop),
                Stop(station: "Stevenage", time: "13:46", platform: "3", type: .stop),
                Stop(station: "London King's Cross", time: "14:03", platform: "4", type: .destination),
            ]
        ),
        Train(
            id: "a002", time: "14:09", destination: "London Paddington", origin: "Bristol Temple Meads",
            via: "Swindon \u{00B7} Reading", platform: "8",
            operator: "Westline Express", operatorCode: "WLX",
            status: .delayed, statusNote: "+4 min", type: "IET-802", carriages: 10, duration: "1h 48m",
            stops: [
                Stop(station: "Bristol Temple Meads", time: "12:21", platform: "5", type: .origin),
                Stop(station: "Bath Spa", time: "12:34", platform: "2", type: .stop),
                Stop(station: "Chippenham", time: "12:46", platform: "1", type: .stop),
                Stop(station: "Swindon", time: "13:02", platform: "3", type: .stop),
                Stop(station: "Didcot Parkway", time: "13:22", platform: "4", type: .stop),
                Stop(station: "Reading", time: "13:35", platform: "7", type: .stop),
                Stop(station: "London Paddington", time: "14:09", platform: "8", type: .destination),
            ]
        ),
        Train(
            id: "a003", time: "14:16", destination: "London St Pancras Intl", origin: "Amsterdam Centraal",
            via: "Rotterdam \u{00B7} Brussels Midi \u{00B7} Lille", platform: "6",
            operator: "Continental Link", operatorCode: "CNL",
            status: .onTime, statusNote: "At platform", type: "TMS-373", carriages: 16, duration: "4h 01m",
            stops: [
                Stop(station: "Amsterdam Centraal", time: "10:16", platform: "15", type: .origin),
                Stop(station: "Rotterdam Centraal", time: "10:55", platform: "11", type: .stop),
                Stop(station: "Brussels Midi", time: "12:04", platform: "3", type: .stop),
                Stop(station: "Lille Europe", time: "12:56", platform: "2", type: .stop),
                Stop(station: "London St Pancras Intl", time: "14:16", platform: "6", type: .destination),
            ]
        ),
        Train(
            id: "a004", time: "14:24", destination: "London Euston", origin: "Birmingham New St",
            via: "Coventry \u{00B7} Milton Keynes", platform: "11",
            operator: "Avanti North", operatorCode: "AVN",
            status: .onTime, statusNote: "On time", type: "C390-P", carriages: 11, duration: "1h 22m",
            stops: [
                Stop(station: "Birmingham New St", time: "13:02", platform: "6", type: .origin),
                Stop(station: "Coventry", time: "13:22", platform: "2", type: .stop),
                Stop(station: "Rugby", time: "13:38", platform: "1", type: .stop),
                Stop(station: "Milton Keynes Central", time: "13:54", platform: "4", type: .stop),
                Stop(station: "Watford Junction", time: "14:12", platform: "5", type: .stop),
                Stop(station: "London Euston", time: "14:24", platform: "11", type: .destination),
            ]
        ),
        Train(
            id: "a005", time: "14:31", destination: "London Waterloo", origin: "Southampton Central",
            via: "Winchester \u{00B7} Basingstoke \u{00B7} Woking", platform: "15",
            operator: "Southern Coast", operatorCode: "SCR",
            status: .onTime, statusNote: "On time", type: "Cl.444", carriages: 10, duration: "1h 18m",
            stops: [
                Stop(station: "Southampton Central", time: "13:13", platform: "3", type: .origin),
                Stop(station: "Winchester", time: "13:28", platform: "2", type: .stop),
                Stop(station: "Basingstoke", time: "13:44", platform: "4", type: .stop),
                Stop(station: "Woking", time: "14:06", platform: "2", type: .stop),
                Stop(station: "Clapham Junction", time: "14:22", platform: "13", type: .stop),
                Stop(station: "London Waterloo", time: "14:31", platform: "15", type: .destination),
            ]
        ),
        Train(
            id: "a006", time: "14:38", destination: "London Paddington", origin: "Oxford",
            via: "Didcot Parkway \u{00B7} Reading", platform: "10",
            operator: "Westline Express", operatorCode: "WLX",
            status: .cancelled, statusNote: "Cancelled", type: "IET-800", carriages: 5, duration: "1h 02m",
            stops: [
                Stop(station: "Oxford", time: "13:36", platform: "3", type: .origin),
                Stop(station: "Didcot Parkway", time: "13:49", platform: "1", type: .stop),
                Stop(station: "Reading", time: "14:02", platform: "4", type: .stop),
                Stop(station: "London Paddington", time: "14:38", platform: "10", type: .destination),
            ]
        ),
        Train(
            id: "a007", time: "14:47", destination: "London Liverpool St", origin: "Stansted Airport",
            via: "Bishop's Stortford \u{00B7} Tottenham Hale", platform: "7",
            operator: "Greater Anglia", operatorCode: "GRA",
            status: .onTime, statusNote: "On time", type: "Cl.745", carriages: 12, duration: "47m",
            stops: [
                Stop(station: "Stansted Airport", time: "14:00", platform: "2", type: .origin),
                Stop(station: "Bishop's Stortford", time: "14:12", platform: "3", type: .stop),
                Stop(station: "Harlow Town", time: "14:22", platform: "1", type: .stop),
                Stop(station: "Tottenham Hale", time: "14:37", platform: "2", type: .stop),
                Stop(station: "London Liverpool St", time: "14:47", platform: "7", type: .destination),
            ]
        ),
    ]
}
