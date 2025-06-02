// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title NUMUSToken
 * @dev ERC-20 token representando una moneda interna (“stablecoin”) 
 *      1 NUMUS = 1 CCOP. Sólo el contrato NummoraLoan podrá mintear/quema.
 *
 * @notice Aquí se corrige el error “No arguments passed to the base constructor”
 *         invocando Ownable(msg.sender) en el constructor.
 */
contract NUMUSToken is ERC20, Ownable {
    /// @notice Dirección del contrato NummoraLoan autorizado para mintear/quema.
    address public nummoraLoan;
    /**
     * @notice Evento que se emite cada vez que NummoraLoan mintea nuevos tokens.]]]]]]
     * @param to      Dirección que recibe los tokens.
     * @param amount  Cantidad de NUMUS creados.
     */
    event NUMUSMinted(address indexed to, uint256 amount);

    /**
     * @notice Evento que se emite cada vez que NummoraLoan quema tokens.
     * @param from    Dirección cuyo balance es quemado.
     * @param amount  Cantidad de NUMUS quemados.
     */
    event NUMUSBurned(address indexed from, uint256 amount);

    /**
     * @dev Sólo el NummoraLoan puede invocar funciones marcadas con este modificador.
     */
    modifier onlyNummoraLoan() {
        require(msg.sender == nummoraLoan, "NUMUSToken: caller is not NummoraLoan");
        _;
    }

    /**
     * @notice Constructor del token NUMUS.
     * @param _nummoraLoan Address del contrato NummoraLoan (puede mintear/quema).
     * @param name         Nombre legible del token (por ejemplo "NUMUS").
     * @param symbol       Símbolo/ticker del token (por ejemplo "NUMUS").
     *
     * @dev <code>ERC20(name, symbol)</code> inicializa la lógica ERC-20,
     *      <code>Ownable(msg.sender)</code> asigna al deployer como owner.
     */
    constructor(
        address _nummoraLoan,
        string memory name,
        string memory symbol
    )
        ERC20(name, symbol)
        Ownable(msg.sender)
    {
        require(_nummoraLoan != address(0), "NUMUSToken: zero address for NummoraLoan");
        nummoraLoan = _nummoraLoan;
    }

    /**
     * @notice Mintea `amount` de tokens NUMUS a la cuenta `to`.
     * @dev Sólo ejecutable por <code>nummoraLoan</code>. Emite {NUMUSMinted}.
     * @param to     Dirección que recibirá los tokens (no debe ser zero).
     * @param amount Cantidad de tokens a emitir (con decimales).
     */
    function mint(address to, uint256 amount) external onlyNummoraLoan {
        require(to != address(0), "NUMUSToken: mint to the zero address");
        _mint(to, amount);
        emit NUMUSMinted(to, amount);
    }

    /**
     * @notice Quema `amount` de tokens NUMUS de la cuenta `from`.
     * @dev Sólo ejecutable por <code>nummoraLoan</code>. Emite {NUMUSBurned}.
     * @param from   Dirección de la cual se quemarán tokens (no debe ser zero).
     * @param amount Cantidad de tokens a quemar (con decimales).
     */
    function burn(address from, uint256 amount) external onlyNummoraLoan {
        require(from != address(0), "NUMUSToken: burn from the zero address");
        _burn(from, amount);
        emit NUMUSBurned(from, amount);
    }

    /**
     * @notice Transfiere `amount` NUMUS tokens desde el caller a `recipient`.
     * @dev Override para añadir validación contra dirección cero.
     * @param recipient Dirección que recibirá los tokens.
     * @param amount    Cantidad de tokens a transferir.
     * @return bool     Retorna true si la transferencia fue exitosa.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        require(recipient != address(0), "NUMUSToken: transfer to the zero address");
        return super.transfer(recipient, amount);
    }

    /**
     * @notice Aprueba que `spender` gaste hasta `amount` tokens NUMUS del caller.
     * @param spender Dirección autorizada a gastar.
     * @param amount  Cantidad máxima permitida.
     * @return bool   Retorna true si la aprobación fue exitosa.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        require(spender != address(0), "NUMUSToken: approve to the zero address");
        return super.approve(spender, amount);
    }

    /**
     * @notice Transfiere `amount` NUMUS tokens de `sender` a `recipient` usando allowance.
     * @param sender    Dirección que posee los tokens.
     * @param recipient Dirección que recibirá los tokens.
     * @param amount    Cantidad de tokens a transferir.
     * @return bool     Retorna true si la transferencia fue exitosa.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        require(sender != address(0), "NUMUSToken: transferFrom sender zero address");
        require(recipient != address(0), "NUMUSToken: transferFrom recipient zero address");
        return super.transferFrom(sender, recipient, amount);
    }

    /**
     * @notice Consulta el balance de tokens NUMUS de una dirección.
     * @param account Dirección a consultar.
     * @return uint256 Balance de tokens en `account`.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return super.balanceOf(account);
    }

    /**
     * @notice Consulta la allowance de `spender` sobre los tokens de `owner`.
     * @param owner   Dirección que otorgó la aprobación.
     * @param spender Dirección con permiso de gastar.
     * @return uint256 Cantidad restante que `spender` puede gastar.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return super.allowance(owner, spender);
    }

    function setNummoraLoan(address _nummoraLoan) external onlyOwner {
        //require(nummoraLoan == address(0), "Already set");
        require(_nummoraLoan != address(0), "Zero address");
        nummoraLoan = _nummoraLoan;
    }
}
//0xdD870fA1b7C4700F2BD7f44238821C26f7392148