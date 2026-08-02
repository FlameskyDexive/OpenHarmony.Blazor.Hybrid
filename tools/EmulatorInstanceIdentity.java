import com.huawei.deveco.common.security.encrypt.KeyManager;
import com.huawei.tools.idea.hvdmanager.utils.AesKit;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.security.SecureRandom;
import java.util.regex.Pattern;

final class EmulatorInstanceIdentity {
    private static final Pattern UUID_PATTERN = Pattern.compile(
        "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$");

    private EmulatorInstanceIdentity() {
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 2) {
            throw new IllegalArgumentException("Usage: EmulatorInstanceIdentity <material-root> <instance-uuid>");
        }

        Path materialRoot = Path.of(args[0]).toAbsolutePath().normalize();
        String instanceUuid = args[1];
        if (!Files.isDirectory(materialRoot)) {
            throw new IllegalArgumentException("Material root does not exist: " + materialRoot);
        }
        if (!UUID_PATTERN.matcher(instanceUuid).matches()) {
            throw new IllegalArgumentException("Invalid emulator instance UUID");
        }

        byte[] key = new KeyManager().readOrCreateKey(materialRoot.toString());
        byte[] encryptedIdentity = AesKit.encrypt(key, createAnonymousIdentity().getBytes(StandardCharsets.UTF_8));
        Path target = Path.of(System.getProperty("java.io.tmpdir"), instanceUuid).toAbsolutePath().normalize();
        Files.write(target, encryptedIdentity, StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING);
        System.out.println(target + " " + encryptedIdentity.length);
    }

    private static String createAnonymousIdentity() {
        SecureRandom random = new SecureRandom();
        char[] identity = new char[16];
        for (int i = 0; i < identity.length; i++) {
            identity[i] = (char) ('0' + random.nextInt(10));
        }
        identity[identity.length - 10] = '0';
        identity[identity.length - 9] = '0';
        return new String(identity);
    }
}
