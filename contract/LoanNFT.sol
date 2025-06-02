// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// IMPORTACIONES: asegúrate de tener instalada la versión 4.x de OpenZeppelin Contracts.
//    npm install @openzeppelin/contracts@^4.8.0
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LoanNFT
 * @notice Implementa un NFT ERC-721 que representa un contrato de préstamo.
 *         Sólo NummoraLoan puede acuñar y quemar estos tokens.
 *
 * – Hereda de ERC721URIStorage para manejar metadatos (tokenURI), acuñar (_safeMint) y quemar (_burn).
 * – Hereda de Ownable para que, en el futuro, el deployer (owner) pueda rotar la dirección de NummoraLoan (opcional).
 * – La dirección de NummoraLoan se almacena como `immutable` para ahorrar gas y garantizar que nunca cambie.
 */
contract LoanNFT is ERC721URIStorage, Ownable {
    /// @notice Dirección del contrato NummoraLoan que tiene permiso para acuñar/quema NFTs.
    address public nummoraLoan;

    /**
     * @notice Se emite cuando NummoraLoan acuña un nuevo NFT para un prestamista.
     * @param to       Dirección que recibe el NFT.
     * @param tokenId  ID único del NFT acuñado (normalmente coincide con `loanId`).
     */
    event LoanNFTMinted(address indexed to, uint256 indexed tokenId);

    /**
     * @notice Se emite cuando NummoraLoan quema (elimina) un NFT al liquidar o cerrar un préstamo.
     * @param tokenId ID del NFT quemado.
     */
    event LoanNFTBurned(uint256 indexed tokenId);

    /**
     * @dev Modifier que restringe la llamada a solo la dirección `nummoraLoan`.
     */
    modifier onlyNummoraLoan() {
        require(msg.sender == nummoraLoan, "LoanNFT: caller is not NummoraLoan");
        _;
    }

    /**
     * @notice Constructor del contrato LoanNFT.
     * @param _nummoraLoan Dirección del contrato NummoraLoan que podrá acuñar/quema estos NFTs.
     * @param name_        Nombre legible de la colección ERC-721 (p.ej. "Nummora Loan Tickets").
     * @param symbol_      Símbolo/ticker para los NFTs (p.ej. "LOAN").
     *
     * @dev
     *   - Invoca ERC721(name_, symbol_) para inicializar la lógica básica del token.
     *   - Invoca Ownable(msg.sender) para asignar al deployer como owner.
     *   - Requiere que `_nummoraLoan` no sea la dirección cero.
     *   - Almacena `nummoraLoan` como `immutable`, por lo que nunca cambiará.
     */
    constructor(
        address _nummoraLoan,
        string memory name_,
        string memory symbol_
    ) ERC721(name_, symbol_) Ownable(msg.sender) {
        require(_nummoraLoan != address(0), "LoanNFT: nummoraLoan cannot be zero");
        nummoraLoan = _nummoraLoan;
    }

    /**
     * @dev Función interna auxiliar para verificar si un token existe.
     *      Usamos `_ownerOf(tokenId) != address(0)` porque `_exists()` ya no es pública.
     *
     * @param tokenId ID del token a consultar.
     * @return true si el token existe, false en caso contrario.
     */
    function _tokenExists(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    /**
     * @notice Acuña un nuevo NFT para `to` con ID `tokenId` y metadatos `uri`.
     * @dev
     *   - Solo ejecutable por la dirección `nummoraLoan`.
     *   - Verifica que `to` no sea la dirección cero.
     *   - Verifica que `_tokenExists(tokenId)` sea false (el token no existe todavía).
     *   - Llama a `_safeMint(to, tokenId)` para acuñar de forma segura.
     *   - Llama a `_setTokenURI(tokenId, uri)` para asignar la metadata JSON.
     *   - Emite el evento LoanNFTMinted.
     *
     * @param to      Dirección del prestamista que recibirá el NFT.
     * @param tokenId ID único del NFT (por lo general coincide con el `loanId`).
     * @param uri     URI apuntando a un JSON con detalles del préstamo:
     *                monto, dirección del deudor, tasas, fechas, estado, etc.
     */
    function mint(
        address to,
        uint256 tokenId,
        string calldata uri
    ) external onlyNummoraLoan {
        require(to != address(0), "LoanNFT: mint to zero address");
        require(!_tokenExists(tokenId), "LoanNFT: tokenId already exists");

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);

        emit LoanNFTMinted(to, tokenId);
    }

    /**
     * @notice Quema (elimina) el NFT con ID `tokenId`. Solo `nummoraLoan` puede invocar.
     * @dev
     *   - Verifica que `_tokenExists(tokenId)` sea true (el NFT existe).
     *   - Llama a `_burn(tokenId)` para:
     *       1) Eliminar el token de la circulación.
     *       2) Eliminar automáticamente el tokenURI asociado.
     *   - Emite el evento LoanNFTBurned.
     *
     * @param tokenId ID del NFT a quemar.
     */
    function burn(uint256 tokenId) external onlyNummoraLoan {
        require(_tokenExists(tokenId), "LoanNFT: non-existent tokenId");
        _burn(tokenId);
        emit LoanNFTBurned(tokenId);
    }

    /**
     * @notice Función pública para verificar si un token existe.
     * @param tokenId ID del token a verificar.
     * @return true si el token existe, false en caso contrario.
     */
    function exists(uint256 tokenId) public view returns (bool) {
        return _tokenExists(tokenId);
    }

    /**
    * @notice (Opcional) Permite al owner ver un mensaje indicando que no puede rotar `nummoraLoan`.
    * @dev    En esta versión, `nummoraLoan` es `immutable`, por lo que no puede reasignarse.
    *         Si en el futuro necesitas cambiarla, tendrás que desplegar una nueva instancia de LoanNFT.
    *
    * @param newNummoraLoan Nueva dirección del contrato NummoraLoan.
    */
    function updateNummoraLoan(address newNummoraLoan) external onlyOwner view {
        require(newNummoraLoan != address(0), "LoanNFT: zero address not allowed");
        revert("LoanNFT: nummoraLoan es immutable; desplegar nuevo contrato");
    }

    function setNummoraLoan(address _nummoraLoan) external onlyOwner {
        //require(nummoraLoan == address(0), "Already set");
        require(_nummoraLoan != address(0), "Zero address");
        nummoraLoan = _nummoraLoan;
    }
}
//0xdD870fA1b7C4700F2BD7f44238821C26f7392148