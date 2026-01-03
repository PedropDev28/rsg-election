-- --------------------------------------------------------

--
-- Table structure for table `election_applications`
--

CREATE TABLE `election_applications` (
  `id` int(11) NOT NULL,
  `citizenid` varchar(50) DEFAULT NULL,
  `name` varchar(100) DEFAULT NULL,
  `age` int(11) DEFAULT NULL,
  `region` varchar(50) DEFAULT NULL,
  `bio` text DEFAULT NULL,
  `approved` tinyint(1) DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `election_applications`
--
ALTER TABLE `election_applications`
  ADD PRIMARY KEY (`id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `election_applications`
--
ALTER TABLE `election_applications`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `election_audit`
--

CREATE TABLE `election_audit` (
  `id` int(11) NOT NULL,
  `actor` varchar(64) DEFAULT NULL,
  `action` varchar(64) DEFAULT NULL,
  `details` text DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

--
-- Indexes for table `election_audit`
--
ALTER TABLE `election_audit`
  ADD PRIMARY KEY (`id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `election_audit`
--
ALTER TABLE `election_audit`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `election_candidacies`
--

CREATE TABLE `election_candidacies` (
  `id` int(11) NOT NULL,
  `election_id` int(11) NOT NULL,
  `identifier` varchar(64) NOT NULL,
  `citizenid` varchar(64) NOT NULL,
  `character_name` varchar(128) NOT NULL,
  `region_hash` varchar(16) NOT NULL,
  `region_alias` varchar(64) NOT NULL,
  `bio` text DEFAULT NULL,
  `portrait` varchar(255) DEFAULT NULL,
  `status` enum('pending','approved','rejected','withdrawn') DEFAULT 'pending',
  `created_at` timestamp NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

--
-- Indexes for table `election_candidacies`
--
ALTER TABLE `election_candidacies`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_elec_region` (`election_id`,`region_hash`),
  ADD KEY `idx_cand_election_status` (`election_id`,`status`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `election_candidacies`
--
ALTER TABLE `election_candidacies`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `election_residents`
--

CREATE TABLE `election_residents` (
  `id` int(11) NOT NULL,
  `identifier` varchar(64) NOT NULL,
  `citizenid` varchar(64) NOT NULL,
  `region_hash` varchar(16) NOT NULL,
  `region_alias` varchar(64) NOT NULL,
  `photo` text DEFAULT NULL,
  `address` text DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `election_residents`
--
ALTER TABLE `election_residents`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_resident` (`citizenid`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `election_residents`
--
ALTER TABLE `election_residents`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `election_votes`
--

CREATE TABLE `election_votes` (
  `id` int(11) NOT NULL,
  `election_id` int(11) NOT NULL,
  `region_hash` varchar(16) NOT NULL,
  `voter_cid` varchar(64) NOT NULL,
  `voter_ident` varchar(64) NOT NULL,
  `candidate_id` int(11) NOT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

--
-- Indexes for table `election_votes`
--
ALTER TABLE `election_votes`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_vote_once` (`election_id`,`voter_cid`),
  ADD KEY `idx_votes_election_voter` (`election_id`,`voter_cid`),
  ADD KEY `idx_votes_election_candidate` (`election_id`,`candidate_id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `election_votes`
--
ALTER TABLE `election_votes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;
COMMIT;

-- --------------------------------------------------------

--
-- Table structure for table `elections`
--

CREATE TABLE `elections` (
  `id` int(11) NOT NULL,
  `region_hash` varchar(16) NOT NULL,
  `region_alias` varchar(64) NOT NULL,
  `phase` enum('idle','registration','campaign','voting','complete') DEFAULT 'idle',
  `reg_start` datetime DEFAULT NULL,
  `reg_end` datetime DEFAULT NULL,
  `vote_start` datetime DEFAULT NULL,
  `vote_end` datetime DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT current_timestamp(),
  `registration_fee` int(11) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_general_ci;

--
-- Indexes for table `elections`
--
ALTER TABLE `elections`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_elections_region_id` (`region_hash`,`id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `elections`
--
ALTER TABLE `elections`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;
COMMIT;
