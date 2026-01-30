-- Assigns geographic regions to countries.
-- Maps each country to its corresponding world region and continent.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2023-11-18

/**
 * Returns the region id for a given country.
 * Based on https://es.wikipedia.org/wiki/Archivo:Regiones_del_mundo.png
 */
 CREATE OR REPLACE FUNCTION dwh.get_country_region (
   osm_id_country INTEGER
 ) RETURNS INTEGER
 LANGUAGE plpgsql
 AS $func$
  DECLARE
   m_region SMALLINT;
  BEGIN
   m_region := 1; -- Indefinida.
   IF (osm_id_country IN (
    -- North America
    1428125, -- Canada
    2184073, -- Greenland
    114686, -- Mexico
    148838, 279001, 279045 -- United States
    )) THEN
    m_region := 2;
   ELSIF (osm_id_country IN (
    -- Central America
    287827, -- Belize
    287667, 2083772, -- Costa Rica
    1520612, -- El Salvador
    7787828, -- France
    1521463, -- Guatemala
    287670, -- Honduras
    287666, 5945359, -- Nicaragua
    287668, 2083783 -- Panama
    )) THEN
    m_region := 3;
   ELSIF (osm_id_country IN (
    -- Antillas
    2177161, -- Anguilla
    536900, -- Antigua and Barbuda
    13928429, -- Aruba
    547511, -- Barbados
    1993208, -- Bermuda
    285454, -- British Virgin Islands
    13928790, -- Bonaire
    2185366, -- Cayman Islands
    307833, -- Cuba
    13928428, -- Curacao
    307823, 3843816, -- Dominica
    307828, -- Dominican Republic
    550727, -- Grenada
    9483303, 9483303, -- Guadeloupe
    307829, -- Haiti
    555017, 5748123, -- Jamaica
    9483304, -- Martinique
    537257, -- Montserrat
    13921959, 14525897, 13928791, -- Netherlands
    9501031, 9501031, -- Saint Barthélemy
    536899, -- Saint Kitts
    550728, -- Saint Lucia
    9501032, -- Saint Martin
    550725, -- Saint Vincent and the Grenadines
    547469, -- The Bahamas
    555717, -- Trinidad and Tobago
    547479 -- Turks and Caicos Islands
    )) THEN
    m_region := 4;
   ELSIF (osm_id_country IN (
    -- South America
    286393, 3394110, 6090144, 7743573, -- Argentina
    16239, 37848, -- Austria
    252645, -- Bolivia
    59470, 5748043, 5748044, -- Brazil
    167454, 5661754, 3969510, -- Chile
    120027, 2083719, 13840086, -- Colombia
    108089, 7751575, 7751576, -- Ecuador
    2185374, 15259894, -- Falkland Islands
    287083, -- Guyana
    13222505, 13222504, --Guyane
    287077, -- Paraguay
    288247, -- Peru
    287082, -- Suriname
    287072, 6089549, -- Uruguay
    272644 -- Venezuela
    )) THEN
    m_region := 5;
   ELSIF (osm_id_country IN (
    -- Western Europe
    9407, -- Andorra
    52411, 7645548, -- Belgium
    50046, 14540303, -- Denmark
    14543431, -- Faroe Island
    54224, 14530729, -- Finland
    2202162, 10731945, 10696345, 2500903, 10737137, -- France
    51477, 3649463, -- Germany
    1278736, -- Gibraltar
    299133, 13955912, 14526317, 13955913, 14543307, -- Iceland
    62273, 4121287, -- Ireland
    62269, -- Isle of Man
    365331, 4769816, -- Italy
    367988, -- Jersey
    1155955, -- Liechtenstein
    2171347, -- Luxembourg
    365307, -- Malta
    1124039, 10696346, -- Monaco
    2323309, 14525913, 3893531, -- Netherlands
    2978650, 13955915, 13955914, -- Norway
    295480, -- Portugal
    54624, -- San Marino
    1311341, 9991145, -- Spain
    52822, 14553467, -- Sweden
    51701, -- Switzerland
    62149, 14531196, 13928359, 14525937, -- United Kingdom
    36989 -- Vatican City
    )) THEN
    m_region := 6;
   ELSIF (osm_id_country IN (
    -- Eastern Europe
    53292, -- Albania
    59065, -- Belarus
    2528142, -- Bosnia and Herzegovina
    3263728, -- British
    186382, -- Bulgaria
    214885, 14991415, -- Croatia
    307787, -- Cyprus
    51684, -- Czechia
    79510, -- Estonia
    192307, -- Greece
    270009, -- Guernsey
    21335, -- Hungary
    72594, -- Latvia
    72596, -- Lithuania
    2088990, -- Kosovo
    58974, -- Moldova
    53296, -- Montenegro
    53293, -- North Macedonia
    49715, 9942670, -- Poland
    90689, -- Romania
    1741311, -- Serbia
    14296, -- Slovakia
    218657, -- Slovenia
    60199, -- Ukraine
    11285925
    )) THEN
    m_region := 7;
   ELSIF (osm_id_country IN (
    -- Caucasus
    364066, -- Armenia
    364110, -- Azerbaijan
    28699 -- Georgia
    )) THEN
    m_region := 8;
   ELSIF (osm_id_country IN (
    -- Siberia
    60189, 13291747 -- Russia
    )) THEN
    m_region := 9;
   ELSIF (osm_id_country IN (
    -- Central Asia
    214665, -- Kazakhstan
    178009, -- Kyrgizstan
    214626, -- Tajikistan
    223026, -- Turkmenistan
    196240 -- Uzbekistan
    )) THEN
    m_region := 10;
   ELSIF (osm_id_country IN (
    -- East Asia
    270056, -- China
    382313, -- Japan
    161033, -- Mongolia
    192734, -- North Korea
    307756, -- South Korea
    449220 -- Taiwan
    )) THEN
    m_region := 11;
   ELSIF (osm_id_country IN (
    -- North Africa
    192756, -- Algeria
    1473947, -- Egypt
    192758, -- Libya
    3630439, -- Morocco
    192757 -- Tunisia
    )) THEN
    m_region := 12;
   ELSIF (osm_id_country IN (
    -- Sub-Saharan Africa
    195267, -- Angola
    192784, 12940096, -- Benin
    3335661, -- Bir Tawil
    1889339, -- Botswana
    192783, -- Burkina Faso
    195269, -- Burundiu
    49898, -- Cambodia
    192830, -- Cameroon
    535774, -- Cape Verde
    192790, -- Central African Republic
    2361304, -- Chad
    535790, -- Comoros
    192795, -- Congo
    192794, -- Congo- Brazaville
    192779, -- Cote d'Ivoire
    192801, -- Djibouti
    192791, -- Equatorial Guinea
    296961, -- Eritrea
    88210, -- Eswatini
    192800, -- Ethiopia
    7787834, -- France
    192793, -- Gabon
    192781, -- Ghana
    192778, -- Guinea
    192776, -- Guinea-Bissau
    192798, -- Kenya
    2093234, -- Lesotho
    192780, -- Liberia
    447325, -- Madagascar
    195290, -- Malawi
    192785, -- Mali
    192763, -- Mauritania
    535828, -- Mauritius
    195273, -- Mozambique
    195266, -- Namibia
    192786, -- Niger
    192787, -- Nigeria
    171496, -- Rwanda
    1964272, -- Saint Helena
    535880, -- Sao Tome and Principe
    192775, -- Senegal
    536765, -- Seychelles
    192777, -- Sierra Leona
    1656678, -- South Sudan
    192789, -- Sudan
    192799, -- Somalia
    87565, 530468, 530469, -- South Africa
    195270, -- Tanzania
    192782, -- Togo
    192774, -- The Gambia
    192796, -- Uganda
    195271, -- Zambia
    195272, -- Zimbabwe
    192797,
    5441968
    )) THEN
    m_region := 13;
   ELSIF (osm_id_country IN (
    -- Middle East
    303427, -- Afghanistan
    378734, -- Barhain
    304938, -- Iran
    304934, -- Iraq
    1473946, -- Israel
    184818, -- Jordan
    1803010, -- Judea
    305099, -- Kuwait
    184843, -- Lebanon
    305138, -- Oman
    1703814, -- Palestinian Territories
    305095, -- Qatar
    307584, -- Saudi Arabia
    184840, -- Syria
    174737, -- Turkiye
    307763, -- United Arab Emirates
    305092 -- Yemen
    )) THEN
    m_region := 14;
   ELSIF (osm_id_country IN (
    -- Indian subcontinent
    184640, -- Bangladesh
    184629, 12931402, -- Bhutan
    1993867, -- British
    304716, -- India
    536773, -- Maldives
    184633, -- Nepal
    307573, -- Pakistan
    536807 -- Sri Lanka
    )) THEN
    m_region := 15;
   ELSIF (osm_id_country IN (
    -- Mainland Southeast Asia
    49903, -- Laos
    2108121, -- Malaysia
    50371, -- Myanmar
    2067731, -- Thailand
    49915 -- Vietnam
    )) THEN
    m_region := 16;
   ELSIF (osm_id_country IN (
    -- Malay arhipelago
    2103120, -- Brunei
    305142, -- East Timor
    536780, -- Singapore
    304751, -- Indonesia
    443174, 4263589 -- Philippines
    )) THEN
    m_region := 17;
   ELSIF (osm_id_country IN (
    -- Pacific Island
    2184233, -- Cook Island
    571747, -- Fiji
    9965686, -- French Polynesia
    571178, -- Kiribati
    571771, -- Marshall Islands
    571802, -- Micronesia
    571804, -- Nauru
    2177258, -- New Caledonia
    556706, 2646063, 2647601, -- New Zealand
    1558556, -- Niue
    571805, -- Palau
    307866, -- Papua New Guinea
    2185375, -- Pitcairn Islands
    1872673, -- Samoa
    1857436, -- Solomon Islands
    1983628, -- South Georgia
    2186600, -- Tokelau
    2186665, -- Tonga
    2177266, -- Tubalu
    2177246 -- Vanuatu
    )) THEN
    m_region := 18;
   ELSIF (osm_id_country IN (
    -- Australia
    80500, 8653540, 2647638 -- Australia
    )) THEN
    m_region := 19;
   ELSIF (osm_id_country IN (
    -- Antartic
    2186646, -- Antartica
    3394111, -- Australia
    3394112, -- British
    3394115, -- Chilean
    3394114, -- France
    2955118,
    3245621,
    3394113
    )) THEN
    m_region := 20;
   END IF;
   RETURN m_region;
  END
 $func$
;
COMMENT ON FUNCTION dwh.get_country_region IS
  'Returns the region of a given country.';

