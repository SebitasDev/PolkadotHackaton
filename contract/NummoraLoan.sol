// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @notice Interface simplificada del token NUMUS (ERC-20 con mint/burn).
 */
interface INUMUSToken is IERC20 {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

/**
 * @notice Interface simplificada del NFT de préstamo (ERC-721 con mint/burn).
 */
interface ILoanNFT is IERC721 {
    function mint(address to, uint256 tokenId, string calldata tokenURI) external;
    function burn(uint256 tokenId) external;
}

/**
 * @title NummoraLoan
 * @notice Contrato principal de la plataforma Nummora que gestiona depósitos de prestamistas,
 *         emisión de préstamos, pagos y retiros, con comisiones y distribución de fondos.
 *         Interactúa con INUMUSToken (ERC-20) y ILoanNFT (ERC-721).
 */
contract NummoraLoan is Ownable {
    /// @notice Token ERC-20 interno (NUMUS) equivalente a CCOP.
    INUMUSToken public immutable numusToken;

    /// @notice Contrato ERC-721 que emite NFTs de préstamo (LoanNFT).
    ILoanNFT public immutable loanNFT;

    /// @notice Comisión fija (1.5%) expresada en basis points (1500/100000).
    uint256 public constant COMMISSION_BASIS = 1500; 
    uint256 public constant BASIS_DIVISOR = 100000;

    /// @notice ID incremental para generar IDs únicos de préstamos.
    uint256 private nextLoanId = 1;

    /// @notice Saldo de tokens NUMUS disponible por prestamista.
    mapping(address => uint256) public prestamistaBalances;

    /// @notice Límite máximo de préstamo permitido por deudor.
    mapping(address => uint256) public deudorLimits;

    /// @notice Datos de cada préstamo registrado por loanId.
    mapping(uint256 => Loan) public loans;

    /// @notice Representa un préstamo activo o cerrado.
    struct Loan {
        uint256 loanId;          // ID único del préstamo
        address prestamista;     // Dirección del prestamista
        address deudor;          // Dirección del deudor
        uint256 amount;          // Monto prestado en NUMUS
        uint256 amountToPay;     // Monto total a pagar en CCOP (incluye interés/comisión)
        bool active;             // True si el préstamo aún está activo
    }

    /// @notice Evento emitido cuando un prestamista deposita CCOP y recibe NUMUS.
    event PrestamistaDeposited(address indexed prestamista, uint256 amountCCOP, uint256 mintedNUMUS);

    /// @notice Evento emitido cuando un prestamista retira NUMUS y recibe CCOP neto.
    event PrestamistaWithdrew(address indexed prestamista, uint256 burnedNUMUS, uint256 amountCCOPNet, uint256 commissionCCOP);

    /// @notice Evento emitido cuando se establece o actualiza el límite de préstamo de un deudor.
    event DeudorLimitSet(address indexed deudor, uint256 newLimitNUMUS);

    /// @notice Evento emitido cuando un deudor solicita un préstamo y se hace match con un prestamista.
    event LoanRequested(
        uint256 indexed loanId,
        address indexed deudor,
        address indexed prestamista,
        uint256 amountNUMUS,
        uint256 amountToPayCCOP
    );

    /// @notice Evento emitido cuando un deudor paga su préstamo.
    event LoanPaid(
        uint256 indexed loanId,
        address indexed deudor,
        address indexed prestamista,
        uint256 paidCCOP,
        uint256 prestamistaShareCCOP,
        uint256 ownerCommissionCCOP
    );

    /// @notice Evento emitido cuando un deudor retira NUMUS y recibe CCOP neto.
    event DeudorWithdrewNUMUS(address indexed deudor, uint256 burnedNUMUS, uint256 amountCCOPNet, uint256 commissionCCOP);

    /**
     * @notice Constructor del contrato NummoraLoan.
     * @param _numusToken Dirección del contrato NUMUSToken (ERC-20).
     * @param _loanNFT    Dirección del contrato LoanNFT (ERC-721).
     */
    constructor(address _numusToken, address _loanNFT) Ownable(msg.sender) {
        require(_numusToken != address(0), "NummoraLoan: numusToken zero address");
        require(_loanNFT != address(0), "NummoraLoan: loanNFT zero address");
        numusToken = INUMUSToken(_numusToken);
        loanNFT = ILoanNFT(_loanNFT);
    }

    /**
     * @notice Deposita CCOP (moneda nativa) como prestamista y recibe NUMUS equivalentes.
     * @dev    La función es payable. El monto de CCOP enviado se convierte 1:1 en NUMUS.
     *         Actualiza el saldo interno de prestamistaBalances.
     */
    function depositarPrestamista() external payable {
        uint256 amountCCOP = msg.value;
        require(amountCCOP > 0, "NummoraLoan: amount must be > 0");

        // Mintear NUMUS equivalentes al prestamista
        numusToken.mint(msg.sender, amountCCOP);
        prestamistaBalances[msg.sender] += amountCCOP;

        emit PrestamistaDeposited(msg.sender, amountCCOP, amountCCOP);
    }

    /**
     * @notice Retira NUMUS como prestamista y recibe CCOP neto después de comisiones.
     * @param amountNUMUS Cantidad de NUMUS a retirar (burn).
     * @dev    Quema los NUMUS en poder del prestamista, calcula comisión 1.5%,
     *         envía CCOP neto al prestamista y la comisión al owner.
     */
    function retirarPrestamista(uint256 amountNUMUS) external {
        require(amountNUMUS > 0, "NummoraLoan: amount must be > 0");
        uint256 balance = prestamistaBalances[msg.sender];
        require(balance >= amountNUMUS, "NummoraLoan: saldo insuficiente");

        // Calcular comisión (1.5%)
        uint256 commission = (amountNUMUS * COMMISSION_BASIS) / BASIS_DIVISOR;
        uint256 netCCOP = amountNUMUS - commission;

        // Actualizar saldo y quemar tokens
        prestamistaBalances[msg.sender] = balance - amountNUMUS;
        numusToken.burn(msg.sender, amountNUMUS);

        // Transferir CCOP neto al prestamista
        payable(msg.sender).transfer(netCCOP);
        // Transferir comisión al owner
        payable(owner()).transfer(commission);

        emit PrestamistaWithdrew(msg.sender, amountNUMUS, netCCOP, commission);
    }

    /**
     * @notice Establece o actualiza el límite de préstamo de un deudor (sólo owner).
     * @param deudor    Dirección del deudor cuyo límite se actualiza.
     * @param newLimit  Nuevo límite en NUMUS que el deudor puede solicitar.
     */
    function setLimitePrestamo(address deudor, uint256 newLimit) external onlyOwner {
        require(deudor != address(0), "NummoraLoan: deudor zero address");
        deudorLimits[deudor] = newLimit;
        emit DeudorLimitSet(deudor, newLimit);
    }

    /**
     * @notice Solicita un préstamo como deudor. Hace match con un prestamista disponible.
     * @param amountNUMUS Cantidad en NUMUS (equivalente a CCOP) que solicita el deudor.
     * @dev    Requiere que amountNUMUS <= deudorLimits[msg.sender].
     *         Busca un prestamista con saldo >= amountNUMUS * 110% (10% extra).
     *         Reserva tokens en el prestamista, envía NUMUS al deudor, emite LoanNFT.
     */
    function solicitarPrestamo(uint256 amountNUMUS) external {
        require(amountNUMUS > 0, "NummoraLoan: amount must be > 0");
        uint256 limit = deudorLimits[msg.sender];
        require(amountNUMUS <= limit, "NummoraLoan: excede limite del deudor");

        // Buscar prestamista que tenga >= amountNUMUS * 110% (cobertura para comisión/interés)
        uint256 requiredBalance = (amountNUMUS * 110) / 100;
        address prestamista = _encontrarPrestamista(requiredBalance);
        require(prestamista != address(0), "NummoraLoan: sin prestamista disponible");

        // Calcular monto a pagar en CCOP (ejemplo: +26.67% → 30k NUMUS → 38k CCOP)
        uint256 amountToPay = (amountNUMUS * 12667) / 10000;

        // Reservar saldo del prestamista
        prestamistaBalances[prestamista] -= requiredBalance;
        // Transferir amountNUMUS de NUMUS al deudor
        numusToken.transferFrom(prestamista, msg.sender, amountNUMUS);

        // Registrar nuevo préstamo
        uint256 loanId = _generateLoanId();
        loans[loanId] = Loan({
            loanId: loanId,
            prestamista: prestamista,
            deudor: msg.sender,
            amount: amountNUMUS,
            amountToPay: amountToPay,
            active: true
        });

        // Armar un tokenURI externo (JSON ya alojado, por ejemplo en IPFS) basado en loanId
        string memory uri = _buildLoanURI(loanId);
        loanNFT.mint(prestamista, loanId, uri);

        emit LoanRequested(loanId, msg.sender, prestamista, amountNUMUS, amountToPay);
    }

    /**
     * @notice Paga el préstamo con loanId, enviando CCOP igual a amountToPay.
     * @param loanId ID del préstamo que el deudor está pagando.
     * @dev    Requiere msg.value == amountToPay; distribuye CCOP al prestamista y owner.
     *         Quema el NFT y marca el préstamo como inactivo.
     */
    function pagarPrestamo(uint256 loanId) external payable {
        Loan storage ln = loans[loanId];
        require(ln.active, "NummoraLoan: prestamo no activo");
        require(ln.deudor == msg.sender, "NummoraLoan: no es tu prestamo");
        require(msg.value == ln.amountToPay, "NummoraLoan: monto incorrecto");

        // Calcular reparto: prestamista recibe principal + 5500 CCOP fijo
        uint256 prestamistaShare = ln.amount + 5500;
        require(prestamistaShare <= msg.value, "NummoraLoan: error calculo share");
        uint256 ownerShare = msg.value - prestamistaShare;

        // Transferir CCOP al prestamista
        payable(ln.prestamista).transfer(prestamistaShare);
        // Transferir comisión/gas al owner
        payable(owner()).transfer(ownerShare);

        // Marcar préstamo como cerrado
        ln.active = false;
        // Quemar el NFT asociado
        loanNFT.burn(loanId);

        emit LoanPaid(loanId, msg.sender, ln.prestamista, msg.value, prestamistaShare, ownerShare);
    }

    /**
     * @notice Retira NUMUS como deudor y recibe CCOP neto (para casos de reembolsos o bonificaciones).
     * @param amountNUMUS Cantidad de NUMUS a convertir de vuelta en CCOP.
     * @dev    Quema NUMUS del deudor, aplica comisión 1.5% y envía CCOP neto.
     */
    function retirarNUMUSDeudor(uint256 amountNUMUS) external {
        require(amountNUMUS > 0, "NummoraLoan: amount must be > 0");
        uint256 balance = numusToken.balanceOf(msg.sender);
        require(balance >= amountNUMUS, "NummoraLoan: saldo insuficiente");

        // Calcular comisión (1.5%)
        uint256 commission = (amountNUMUS * COMMISSION_BASIS) / BASIS_DIVISOR;
        uint256 netCCOP = amountNUMUS - commission;

        // Quemar NUMUS del deudor
        numusToken.burn(msg.sender, amountNUMUS);

        // Enviar CCOP neto al deudor
        payable(msg.sender).transfer(netCCOP);
        // Transferir comisión al owner
        payable(owner()).transfer(commission);

        emit DeudorWithdrewNUMUS(msg.sender, amountNUMUS, netCCOP, commission);
    }

    /**
     * @dev Interna: Genera y retorna un nuevo ID único de préstamo.
     */
    function _generateLoanId() internal returns (uint256) {
        return nextLoanId++;
    }

    /**
     * @dev Interna: Busca un prestamista con saldo >= requiredBalance.
     *      Esta implementación de ejemplo no es escalable: en producción usarías
     *      una lista dinámica o estructura de datos indexada (p.ej., min-heap).
     *      Aquí devolvemos address(0) a menos que el owner cumpla el requisito.
     *
     * @param requiredBalance Monto mínimo requerido en prestamistaBalances.
     * @return address del prestamista encontrado, o address(0) si ninguno cumple.
     */
    function _encontrarPrestamista(uint256 requiredBalance) internal view returns (address) {
        // Ejemplo simplificado: verifica sólo al owner como préstamo único.
        if (prestamistaBalances[owner()] >= requiredBalance) {
            return owner();
        }
        return address(0);
    }

    /**
     * @dev Interna: Construye un tokenURI basado sólo en loanId. En producción,
     *      subirías JSON a IPFS y retornarías algo como "ipfs://<hash>/<loanId>.json".
     *
     * @param loanId ID del préstamo para el que se genera URI.
     * @return string URI a los metadatos JSON del préstamo.
     */
    function _buildLoanURI(uint256 loanId) internal pure returns (string memory) {
        return string(abi.encodePacked(
            "https://api.nummora.com/loans/",
            _uint2str(loanId),
            ".json"
        ));
    }

    /**
     * @dev Interna: Convierte un uint256 a string decimal.
     */
    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 temp = _i;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (_i != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(_i % 10)));
            _i /= 10;
        }
        return string(buffer);
    }

    /**
     * @notice Permite al contrato recibir CCOP directamente.
     */
    receive() external payable {}

    /**
     * @notice Fallback para recepción de CCOP.
     */
    fallback() external payable {}
}
