package com.sysnormal.services.security.sso;

import jakarta.annotation.PostConstruct;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class SsoApplication {

	public static void main(String[] args) {
		SpringApplication.run(SsoApplication.class, args);
	}

	@PostConstruct
	public void testClassLoader() {
		try {
			Class.forName(
					"com.sysnormal.starters.security.sso.sso_starter.database.migrations.V1__CreateAllTablesAndConstraints"
			);
			System.out.println("xxxxxxxxxxxxx Migration class FOUND");
		} catch (ClassNotFoundException e) {
			System.out.println("zzzzzzzzzzzzzzz Migration class NOT FOUND");
		}
	}

}
