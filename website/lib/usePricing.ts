"use client";

import { useEffect, useState, useCallback, useSyncExternalStore } from "react";
import {
  COUNTRY_CURRENCY_MAP,
  detectUserCountry,
  isLocalEnvironment,
  type LocalizedPriceData,
} from "./pricing";

// In-memory client-side price cache to eliminate duplicate network calls
const clientPriceCache: Record<string, LocalizedPriceData> = {};

function subscribeMockCountry(callback: () => void) {
  if (typeof window === "undefined" || !isLocalEnvironment()) return () => {};
  window.addEventListener("pt_mock_country_changed", callback);
  window.addEventListener("storage", callback);
  return () => {
    window.removeEventListener("pt_mock_country_changed", callback);
    window.removeEventListener("storage", callback);
  };
}

function getMockCountrySnapshot(): string | null {
  if (typeof window === "undefined" || !isLocalEnvironment()) return null;
  const urlParams = new URLSearchParams(window.location.search);
  const paramMock = urlParams.get("mock_country") || urlParams.get("country");
  const storedMock = localStorage.getItem("synctogether_mock_country");
  const activeMock = paramMock || storedMock || null;
  return activeMock ? activeMock.toUpperCase() : null;
}

function getMockCountryServerSnapshot(): string | null {
  return null;
}

export function usePricing() {
  const [data, setData] = useState<LocalizedPriceData>({
    monthlyFormatted: "$3.99",
    monthlyAmount: 3.99,
    annualFormatted: "$29.99",
    annualAmount: 29.99,
    monthlyEquivalentFormatted: "$2.49 / mo",
    monthlyEquivalentAmount: 2.49,
    currencyCode: "USD",
    currencySymbol: "$",
    countryCode: "US",
    savingsPct: "37%",
  });
  const [isLoading, setIsLoading] = useState<boolean>(true);

  // Synchronize mock country cleanly across server/client with zero hydration mismatch
  const mockCountry = useSyncExternalStore(
    subscribeMockCountry,
    getMockCountrySnapshot,
    getMockCountryServerSnapshot
  );

  const setMockCountry = useCallback((country: string | null) => {
    if (!isLocalEnvironment()) return;
    if (country) {
      const upper = country.toUpperCase();
      localStorage.setItem("synctogether_mock_country", upper);
    } else {
      localStorage.removeItem("synctogether_mock_country");
    }
    if (typeof window !== "undefined") {
      window.dispatchEvent(new CustomEvent("pt_mock_country_changed", { detail: country }));
    }
  }, []);

  // Expose global helper for automated testing and developer console (local development only)
  useEffect(() => {
    if (typeof window !== "undefined" && isLocalEnvironment()) {
      (window as unknown as { __setMockCountry?: (c: string | null) => void }).__setMockCountry = setMockCountry;
    }
    return () => {
      if (typeof window !== "undefined") {
        delete (window as unknown as { __setMockCountry?: (c: string | null) => void }).__setMockCountry;
      }
    };
  }, [setMockCountry]);

  const fetchPricing = useCallback(async () => {
    const country = mockCountry || detectUserCountry();
    const countryConfig = COUNTRY_CURRENCY_MAP[country] || COUNTRY_CURRENCY_MAP["US"];
    const targetCurrency = countryConfig.currency;

    // Check memory cache first
    if (clientPriceCache[country]) {
      setData(clientPriceCache[country]);
      setIsLoading(false);
      return;
    }

    setIsLoading(true);

    try {
      // The server asks whichever provider is active, then falls back to the
      // static localised table.
      const res = await fetch(`/api/billing/prices?country=${country}&currency=${targetCurrency}`);
      if (res.ok) {
        const apiData = await res.json();
        const result: LocalizedPriceData = {
          monthlyFormatted: apiData.monthlyFormatted,
          monthlyAmount: apiData.monthlyAmount,
          annualFormatted: apiData.annualFormatted,
          annualAmount: apiData.annualAmount,
          monthlyEquivalentFormatted: apiData.monthlyEquivalentFormatted,
          monthlyEquivalentAmount: apiData.monthlyEquivalentAmount,
          currencyCode: apiData.currencyCode,
          currencySymbol: apiData.currencySymbol,
          countryCode: apiData.countryCode,
          savingsPct: apiData.savingsPct,
          rawResponse: apiData,
        };
        clientPriceCache[country] = result;
        setData(result);
      }
    } catch (err) {
      console.error("Failed to load localized prices:", err);
    } finally {
      setIsLoading(false);
    }
  }, [mockCountry]);

  useEffect(() => {
    let ignore = false;
    async function load() {
      if (!ignore) {
        await fetchPricing();
      }
    }
    load();
    return () => {
      ignore = true;
    };
  }, [fetchPricing]);

  return {
    ...data,
    isLoading,
    mockCountry,
    isMocked: Boolean(mockCountry),
    setMockCountry,
    refetch: fetchPricing,
  };
}
