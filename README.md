# Crypto Ecosystems

🌲 Crypto Ecosystems is a taxonomy of open source blockchain, Web3, cryptocurrency, and decentralized ecosystems and tying them to GitHub organizations and code repositories.

This repository is not complete, and hopefully it never is as there are new ecosystems and repositories created every day.

# How to use this taxonomy
The taxonomy can be used to generate the set of crypto ecosystems, their corresponding sub ecosystems, and repositories at a particular time.

## How to update the taxonomy
There is a domain specific language (DSL) containing the keywords that can make changes to the taxonomy.  You specify migrations by using files of the format
```bash
migrations/YYYY-DD-MMTHHMMDD_description_of_your_migration
```

Some examples migration files:
```bash
migrations/2009-01-03T181500_add_bitcoin
migrations/2015-07-30T152613_add_ethereum
```

#### Data Format

#### Example: Adding an ecosystem
```bash
# Add ecosystems with the ecoadd keyword.  Comments are allowed with the # character.
ecoadd Lightning
# Add repos to ecosystems using the repadd keyword
repadd Lightning https://github.com/lightningnetwork/lnd #protocol
# Connect ecosystems using the ecocon keyword.
# The following connects Lighting as a sub ecosystem of Bitcoin.
ecocon Bitcoin Lighting
```

### Option 2: Complete the Ecosystem Submission form

If you are not a developer or you find making a commit too difficult, you can use this Airtable based alternative below.

You can [visit the form here](https://airtable.com/shrN4vZMlBLm3Dap8), fill it, submit it and we'll take care of the rest :)

## How to Give Attribution For Usage of the Electric Capital Crypto Ecosystems

The repository is licensed under [MIT license with attribution](https://github.com/electric-capital/crypto-ecosystems/blob/master/LICENSE).

To use the Electric Capital Crypto Ecosystems Map in your project, you will need an attribution.

Attribution needs to have 3 components:

1. Source: “Electric Capital Crypto Ecosystems”
2. Link: https://github.com/electric-capital/crypto-ecosystems
3. Logo: [Link to logo](static/electric_capital_logo_transparent.png)

Optional:
Everyone in the crypto ecosystem benefits from additions to this repository.
It is a help to everyone to include an ask to contribute next to your attribution.

Sample request language: "If you’re working in open source crypto, submit your repository here to be counted."

<ins>Sample attribution</ins>

Data Source: [Electric Capital Crypto Ecosystems](https://github.com/electric-capital/crypto-ecosystems)

If you’re working in open source crypto, submit your repository [here](https://github.com/electric-capital/crypto-ecosystems) to be counted.

## How to Contribute (Step-by-Step Guide)

### Option 1: Adding a new ecosystem (e.g. blockchain)

### Add a new sub ecosystem

### Add a new repo

Thank you for contributing and for reading the contribution guide! ❤️
