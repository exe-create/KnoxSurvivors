import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.security.MessageDigest;
import java.util.Arrays;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import me.zed_0xff.zombie_buddy.KnownAuthors;
import me.zed_0xff.zombie_buddy.SteamWorkshop.SteamID64;
import me.zed_0xff.zombie_buddy.ZBSVerifier;
import zb.org.bouncycastle.crypto.params.Ed25519PrivateKeyParameters;
import zb.org.bouncycastle.crypto.signers.Ed25519Signer;
import zb.org.bouncycastle.crypto.util.PrivateKeyFactory;

/** Release tooling only: documented ZBS format, installed ZombieBuddy crypto/verifier.
 * Never packaged in the mod. No key generation, profile editing or trust-store access.
 */
public final class ZbsTool {
    private static final HexFormat HEX = HexFormat.of();

    private static String hash(Path jar) throws Exception {
        var digest = MessageDigest.getInstance("SHA-256");
        try (var input = Files.newInputStream(jar)) {
            byte[] buffer = new byte[8192];
            int count;
            while ((count = input.read(buffer)) != -1) digest.update(buffer, 0, count);
        }
        return HEX.formatHex(digest.digest());
    }

    private static SteamID64 author(String id) {
        if (!id.matches("[0-9]{17}")) throw new IllegalArgumentException("SteamID64 must be 17 digits");
        return new SteamID64(id);
    }

    private static ZBSVerifier.Verification verify(Path jar, String id, String publicKey) throws Exception {
        if (!publicKey.matches("[0-9a-fA-F]{64}")) throw new IllegalArgumentException("Public key must be 32-byte hex");
        var sid = author(id);
        var entry = new KnownAuthors.AuthorEntry();
        entry.id = sid;
        entry.name = "Explicit verification key";
        entry.keys = List.of(publicKey);
        // A supplied key tests cryptography/uploader binding, not public discovery or user trust.
        return ZBSVerifier.verify(jar, Path.of(jar + ".zbs"), hash(jar), sid, Map.of(sid, entry));
    }

    public static void main(String[] args) throws Exception {
        if (args.length == 3 && args[0].equals("verify-published")) {
            Path jar = Path.of(args[1]);
            var result = ZBSVerifier.verify(jar, Path.of(jar + ".zbs"), hash(jar), author(args[2]));
            System.out.println("Installed ZombieBuddy public-identity check: " + result.getClass().getSimpleName());
            System.out.println(ZBSVerifier.noticeForUi(result));
            if (!(result instanceof ZBSVerifier.ValidSignature)) throw new SecurityException("Public author identity is not established or signature failed");
            return;
        }
        if (args.length == 2 && args[0].equals("inspect-unsigned")) {
            Path jar = Path.of(args[1]);
            if (Files.exists(Path.of(jar + ".zbs"))) throw new IllegalArgumentException("Use verify for signed artifacts");
            var result = ZBSVerifier.verify(jar, Path.of(jar + ".zbs"), hash(jar), null, Map.of());
            System.out.println(result.getClass().getSimpleName());
            System.out.println("UI: " + ZBSVerifier.noticeForUi(result));
            System.out.println("SHA256: " + hash(jar));
            if (!(result instanceof ZBSVerifier.MissingSignature)) throw new IllegalStateException("Unexpected result");
            return;
        }
        if (args.length != 4) throw new IllegalArgumentException("sign JAR SteamID64 PRIVATE_KEY_DER | verify JAR UPLOADER_ID PUBLIC_KEY_HEX");
        Path jar = Path.of(args[1]);
        author(args[2]);
        if (args[0].equals("verify")) {
            var result = verify(jar, args[2], args[3]);
            System.out.println("Installed ZombieBuddy: " + result.getClass().getSimpleName());
            if (!(result instanceof ZBSVerifier.ValidSignature)) throw new SecurityException(result.shortMessage);
            System.out.println("PASS: JAR bytes, signature and expected uploader match supplied public key; public discovery/trust not tested");
        } else if (args[0].equals("sign")) {
            String before = hash(jar);
            byte[] encoded = Files.readAllBytes(Path.of(args[3]));
            String publicKey;
            byte[] signature;
            try {
                var key = (Ed25519PrivateKeyParameters) PrivateKeyFactory.createKey(encoded);
                publicKey = HEX.formatHex(key.generatePublicKey().getEncoded());
                byte[] message = ("ZBS:" + args[2] + ":" + before).getBytes(StandardCharsets.UTF_8);
                var signer = new Ed25519Signer();
                signer.init(true, key);
                signer.update(message, 0, message.length);
                signature = signer.generateSignature();
            } finally {
                Arrays.fill(encoded, (byte) 0);
            }
            if (!hash(jar).equals(before)) throw new SecurityException("JAR changed while signing");
            Files.writeString(Path.of(jar + ".zbs"), "ZBS\nSteamID64:" + args[2] + "\nSignature:" + HEX.formatHex(signature) + "\n",
                StandardCharsets.UTF_8, StandardOpenOption.CREATE_NEW);
            if (!(verify(jar, args[2], publicKey) instanceof ZBSVerifier.ValidSignature)) throw new SecurityException("Generated signature failed installed verifier");
            if (!hash(jar).equals(before)) throw new SecurityException("JAR changed after signing");
            System.out.println("PASS: detached signature verified by installed ZombieBuddy; JAR unchanged");
            System.out.println("Public key for owner publication: JavaModZBS:" + publicKey);
        } else throw new IllegalArgumentException("Unknown command");
    }
}
