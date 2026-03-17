with Ada.Numerics.Generic_Elementary_Functions;
with Phi_function;
with Beta_function;
with Gamma_function;
with Generic_Random_Functions;

package body SData.Statistics is

   package REF is new Ada.Numerics.Generic_Elementary_Functions (Long_Float);
   use REF;

   package Long_Phi is new Phi_function (Long_Float);
   package Long_Beta is new Beta_function (Long_Float);
   package Long_Gamma is new Gamma_function (Long_Float);
   package Long_Rand_Funcs is new Generic_Random_Functions (Long_Float);

   ------------------------
   -- Ensure_Random_Init --
   ------------------------
   procedure Ensure_Random_Init is
   begin
      if not Initialized then
         Ada.Numerics.Float_Random.Reset (Generator);
         Initialized := True;
      end if;
   end Ensure_Random_Init;

   procedure Set_Seed (Seed : Integer) is
   begin
      Ada.Numerics.Float_Random.Reset (Generator, Seed);
      Initialized := True;
   end Set_Seed;

   function Uniform_Random return Float is
   begin
      Ensure_Random_Init;
      return Float (Ada.Numerics.Float_Random.Random (Generator));
   end Uniform_Random;

   ----------------------
   -- Incomplete_Gamma --
   ----------------------
   --  Regularized lower incomplete gamma function P(a, x)
   function Incomplete_Gamma_P (A, X : Long_Float) return Long_Float is
      ITMAX : constant := 100;
      EPS   : constant := 3.0e-14;
      FPMIN : constant := 1.0e-100;

      function G_Series (A, X : Long_Float) return Long_Float is
         Sum, Del, AP : Long_Float;
      begin
         AP := A;
         Sum := 1.0 / A;
         Del := Sum;
         for I in 1 .. ITMAX loop
            AP := AP + 1.0;
            Del := Del * X / AP;
            Sum := Sum + Del;
            exit when abs (Del) < abs (Sum) * EPS;
         end loop;
         return Sum * Exp (-X + A * Log (X) - Long_Gamma.Log_Gamma (A));
      end G_Series;

      function G_CF (A, X : Long_Float) return Long_Float is
         B, C, D, Del, H : Long_Float;
         AN : Long_Float;
      begin
         B := X + 1.0 - A;
         C := 1.0 / FPMIN;
         D := 1.0 / B;
         H := D;
         for I in 1 .. ITMAX loop
            AN := -Long_Float (I) * (Long_Float (I) - A);
            B := B + 2.0;
            D := AN * D + B;
            if abs (D) < FPMIN then D := FPMIN; end if;
            C := B + AN / C;
            if abs (C) < FPMIN then C := FPMIN; end if;
            D := 1.0 / D;
            Del := D * C;
            H := H * Del;
            exit when abs (Del - 1.0) < EPS;
         end loop;
         return Exp (-X + A * Log (X) - Long_Gamma.Log_Gamma (A)) * H;
      end G_CF;

   begin
      if X < 0.0 or A <= 0.0 then return 0.0; end if;
      if X < A + 1.0 then
         return G_Series (A, X);
      else
         return 1.0 - G_CF (A, X);
      end if;
   end Incomplete_Gamma_P;

   -----------
   -- Z_PDF --
   -----------
   function Z_PDF (Z : Float) return Float is
      Constant_Part : constant Long_Float := 1.0 / Sqrt (2.0 * Ada.Numerics.Pi);
   begin
      return Float (Constant_Part * Exp (-0.5 * (Long_Float (Z)**2)));
   end Z_PDF;

   -----------
   -- Z_CDF --
   -----------
   function Z_CDF (Z : Float) return Float is
   begin
      return Float (Long_Phi.Phi (Long_Float (Z)));
   end Z_CDF;

   -----------
   -- Z_IDF --
   -----------
   function Z_IDF (P : Float) return Float is
   begin
      if P <= 0.0 or P >= 1.0 then raise Constraint_Error with "Probability must be in (0,1)"; end if;
      return Float (Long_Phi.Inverse_Phi (Long_Float (P)));
   end Z_IDF;

   ----------------
   -- Normal_PDF --
   ----------------
   function Normal_PDF (X, Mean, Std_Dev : Float) return Float is
   begin
      if Std_Dev <= 0.0 then raise Constraint_Error with "Standard deviation must be positive"; end if;
      return Z_PDF ((X - Mean) / Std_Dev) / Std_Dev;
   end Normal_PDF;

   ----------------
   -- Normal_CDF --
   ----------------
   function Normal_CDF (X, Mean, Std_Dev : Float) return Float is
   begin
      if Std_Dev <= 0.0 then raise Constraint_Error with "Standard deviation must be positive"; end if;
      return Z_CDF ((X - Mean) / Std_Dev);
   end Normal_CDF;

   ----------------
   -- Normal_IDF --
   ----------------
   function Normal_IDF (P, Mean, Std_Dev : Float) return Float is
   begin
      if Std_Dev <= 0.0 then raise Constraint_Error with "Standard deviation must be positive"; end if;
      return Mean + Z_IDF (P) * Std_Dev;
   end Normal_IDF;

   ---------------
   -- Normal_RN --
   ---------------
   function Normal_RN (Mean, Std_Dev : Float) return Float is
      N1, N2 : Long_Float;
   begin
      Ensure_Random_Init;
      Long_Rand_Funcs.Box_Muller (Long_Float (Ada.Numerics.Float_Random.Random (Generator)), Long_Float (Ada.Numerics.Float_Random.Random (Generator)), N1, N2);
      return Float (Long_Float (Mean) + N1 * Long_Float (Std_Dev));
   end Normal_RN;

   -----------------
   -- Uniform_PDF --
   -----------------
   function Uniform_PDF (X, Lower, Upper : Float) return Float is
   begin
      if Lower >= Upper then raise Constraint_Error with "Lower bound must be less than Upper bound"; end if;
      return (if X >= Lower and X <= Upper then 1.0 / (Upper - Lower) else 0.0);
   end Uniform_PDF;

   -----------------
   -- Uniform_CDF --
   -----------------
   function Uniform_CDF (X, Lower, Upper : Float) return Float is
   begin
      if Lower >= Upper then raise Constraint_Error with "Lower bound must be less than Upper bound"; end if;
      if X < Lower then return 0.0; elsif X > Upper then return 1.0; else return (X - Lower) / (Upper - Lower); end if;
   end Uniform_CDF;

   -----------------
   -- Uniform_IDF --
   -----------------
   function Uniform_IDF (P, Lower, Upper : Float) return Float is
   begin
      if Lower >= Upper then raise Constraint_Error with "Lower bound must be less than Upper bound"; end if;
      return Lower + P * (Upper - Lower);
   end Uniform_IDF;

   ----------------
   -- Uniform_RN --
   ----------------
   function Uniform_RN (Lower, Upper : Float) return Float is
   begin
      Ensure_Random_Init;
      return Lower + Ada.Numerics.Float_Random.Random (Generator) * (Upper - Lower);
   end Uniform_RN;

   ---------------------
   -- Exponential_PDF --
   ---------------------
   function Exponential_PDF (X, Rate : Float) return Float is
   begin
      if Rate <= 0.0 then raise Constraint_Error with "Rate must be positive"; end if;
      return (if X < 0.0 then 0.0 else Float (Long_Float (Rate) * Exp (-Long_Float (Rate) * Long_Float (X))));
   end Exponential_PDF;

   ---------------------
   -- Exponential_CDF --
   ---------------------
   function Exponential_CDF (X, Rate : Float) return Float is
   begin
      if Rate <= 0.0 then raise Constraint_Error with "Rate must be positive"; end if;
      return (if X < 0.0 then 0.0 else Float (1.0 - Exp (-Long_Float (Rate) * Long_Float (X))));
   end Exponential_CDF;

   ---------------------
   -- Exponential_IDF --
   ---------------------
   function Exponential_IDF (P, Rate : Float) return Float is
   begin
      if Rate <= 0.0 then raise Constraint_Error with "Rate must be positive"; end if;
      if P < 0.0 or P >= 1.0 then raise Constraint_Error with "P must be in [0,1)"; end if;
      return Float (-Log (1.0 - Long_Float (P)) / Long_Float (Rate));
   end Exponential_IDF;

   --------------------
   -- Exponential_RN --
   --------------------
   function Exponential_RN (Rate : Float) return Float is
   begin
      Ensure_Random_Init;
      return Exponential_IDF (Ada.Numerics.Float_Random.Random (Generator), Rate);
   end Exponential_RN;

   --------------
   -- Beta_PDF --
   --------------
   function Beta_PDF (X, Alpha, Beta : Float) return Float is
   begin
      if Alpha <= 0.0 or Beta <= 0.0 then raise Constraint_Error with "Parameters must be positive"; end if;
      if X < 0.0 or X > 1.0 then return 0.0; end if;
      return Float ((Long_Float (X)**(Long_Float (Alpha) - 1.0) * (1.0 - Long_Float (X))**(Long_Float (Beta) - 1.0)) / Long_Beta.Beta (Long_Float (Alpha), Long_Float (Beta)));
   end Beta_PDF;

   --------------
   -- Beta_CDF --
   --------------
   function Beta_CDF (X, Alpha, Beta : Float) return Float is
   begin
      if X <= 0.0 then return 0.0; elsif X >= 1.0 then return 1.0; end if;
      return Float (Long_Beta.Regularized_Beta (Long_Float (X), Long_Float (Alpha), Long_Float (Beta)));
   end Beta_CDF;

   --------------
   -- Beta_IDF --
   --------------
   function Beta_IDF (P, Alpha, Beta : Float) return Float is
   begin
      return Float (Long_Beta.Inverse_Regularized_Beta (Long_Float (P), Long_Float (Alpha), Long_Float (Beta)));
   end Beta_IDF;

   -----------------
   -- Poisson_PMF --
   -----------------
   function Poisson_PMF (K, Mean : Float) return Float is
      KI : constant Long_Float := Long_Float (Float'Floor (K));
   begin
      if Mean <= 0.0 then raise Constraint_Error with "Mean must be positive"; end if;
      if K < 0.0 then return 0.0; end if;
      return Float (Exp (-Long_Float (Mean) + KI * Log (Long_Float (Mean)) - Long_Gamma.Log_Gamma (KI + 1.0)));
   end Poisson_PMF;

   -----------------
   -- Poisson_CDF --
   -----------------
   function Poisson_CDF (K, Mean : Float) return Float is
      KI : constant Integer := Integer (Float'Floor (K));
      Sum : Long_Float := 0.0;
   begin
      if Mean <= 0.0 then raise Constraint_Error with "Mean must be positive"; end if;
      if K < 0.0 then return 0.0; end if;
      for I in 0 .. KI loop Sum := Sum + Long_Float (Poisson_PMF (Float (I), Mean)); end loop;
      return Float (Sum);
   end Poisson_CDF;

   ----------------
   -- Poisson_RN --
   ----------------
   function Poisson_RN (Mean : Float) return Float is
      function U return Long_Float is
      begin
         Ensure_Random_Init;
         return Long_Float (Ada.Numerics.Float_Random.Random (Generator));
      end U;
      function Poisson_Func is new Long_Rand_Funcs.Poisson (U);
   begin
      return Float (Long_Float (Poisson_Func (Long_Float (Mean))));
   end Poisson_RN;

   ---------------
   -- Gamma_PDF --
   ---------------
   function Gamma_PDF (X, Alpha, Beta : Float) return Float is
   begin
      if Alpha <= 0.0 or Beta <= 0.0 then raise Constraint_Error with "Parameters must be positive"; end if;
      if X <= 0.0 then return 0.0; end if;
      return Float (Exp (Long_Float (Alpha) * Log (Long_Float (Beta)) + (Long_Float (Alpha) - 1.0) * Log (Long_Float (X)) - Long_Float (Beta) * Long_Float (X) - Long_Gamma.Log_Gamma (Long_Float (Alpha))));
   end Gamma_PDF;

   ---------------
   -- Gamma_CDF --
   ---------------
   function Gamma_CDF (X, Alpha, Beta : Float) return Float is
   begin
      if X <= 0.0 then return 0.0; end if;
      return Float (Incomplete_Gamma_P (Long_Float (Alpha), Long_Float (Beta) * Long_Float (X)));
   end Gamma_CDF;

   --------------
   -- Gamma_RN --
   --------------
   --  Using Marsaglia and Tsang's method (2000)
   function Gamma_RN (Alpha, Beta : Float) return Float is
      A : constant Long_Float := Long_Float (Alpha);
      B : constant Long_Float := Long_Float (Beta);
      D, C, X, V, U : Long_Float;
   begin
      Ensure_Random_Init;
      if A < 1.0 then
         --  Marsaglia and Tsang's method requires A >= 1.
         --  Relationship: Gamma(A, B) = Gamma(A+1, B) * U^(1/A)
         return Gamma_RN (Alpha + 1.0, Beta) * Float (Long_Float (Ada.Numerics.Float_Random.Random (Generator)) ** (1.0 / A));
      end if;

      D := A - 1.0 / 3.0;
      C := 1.0 / Sqrt (9.0 * D);
      loop
         loop
            X := Long_Float (Z_IDF (Ada.Numerics.Float_Random.Random (Generator)));
            V := 1.0 + C * X;
            exit when V > 0.0;
         end loop;
         V := V**3;
         U := Long_Float (Ada.Numerics.Float_Random.Random (Generator));
         exit when U < 1.0 - 0.0331 * (X**4) or else Log (U) < 0.5 * (X**2) + D * (1.0 - V + Log (V));
      end loop;
      return Float (D * V / B);
   end Gamma_RN;

   --------------------
   -- Chi_Square_PDF --
   --------------------
   function Chi_Square_PDF (X, DF : Float) return Float is
   begin
      return Gamma_PDF (X, DF / 2.0, 0.5);
   end Chi_Square_PDF;

   --------------------
   -- Chi_Square_CDF --
   --------------------
   function Chi_Square_CDF (X, DF : Float) return Float is
   begin
      return Gamma_CDF (X, DF / 2.0, 0.5);
   end Chi_Square_CDF;

   -------------------
   -- Student_T_PDF --
   -------------------
   function Student_T_PDF (T, DF : Float) return Float is
      V : constant Long_Float := Long_Float (DF);
      X : constant Long_Float := Long_Float (T);
   begin
      return Float (Exp (Long_Gamma.Log_Gamma ((V + 1.0) / 2.0) - Long_Gamma.Log_Gamma (V / 2.0)) / (Sqrt (V * Ada.Numerics.Pi) * (1.0 + (X**2) / V)**((V + 1.0) / 2.0)));
   end Student_T_PDF;

   -------------------
   -- Student_T_CDF --
   -------------------
   function Student_T_CDF (T, DF : Float) return Float is
      V : constant Long_Float := Long_Float (DF);
      X : constant Long_Float := Long_Float (T);
      W : Long_Float;
   begin
      W := V / (V + X**2);
      if X > 0.0 then
         return 1.0 - 0.5 * Float (Long_Beta.Regularized_Beta (W, V / 2.0, 0.5));
      else
         return 0.5 * Float (Long_Beta.Regularized_Beta (W, V / 2.0, 0.5));
      end if;
   end Student_T_CDF;

   -----------
   -- F_PDF --
   -----------
   function F_PDF (X, DF1, DF2 : Float) return Float is
      V1 : constant Long_Float := Long_Float (DF1);
      V2 : constant Long_Float := Long_Float (DF2);
      XV : constant Long_Float := Long_Float (X);
   begin
      if XV <= 0.0 then return 0.0; end if;
      return Float (Sqrt (((V1 * XV)**V1 * V2**V2) / (V1 * XV + V2)**(V1 + V2)) / (XV * Long_Beta.Beta (V1 / 2.0, V2 / 2.0)));
   end F_PDF;

   -----------
   -- F_CDF --
   -----------
   function F_CDF (X, DF1, DF2 : Float) return Float is
      V1 : constant Long_Float := Long_Float (DF1);
      V2 : constant Long_Float := Long_Float (DF2);
      XV : constant Long_Float := Long_Float (X);
      W : Long_Float;
   begin
      if XV <= 0.0 then return 0.0; end if;
      W := (V1 * XV) / (V1 * XV + V2);
      return Float (Long_Beta.Regularized_Beta (W, V1 / 2.0, V2 / 2.0));
   end F_CDF;

   ------------------
   -- Binomial_PMF --
   ------------------
   function Binomial_PMF (K, N, P : Float) return Float is
      KI : constant Long_Float := Long_Float (Float'Floor (K));
      NI : constant Long_Float := Long_Float (Float'Floor (N));
      PF : constant Long_Float := Long_Float (P);
   begin
      if PF < 0.0 or PF > 1.0 or NI < 0.0 then raise Constraint_Error with "Invalid Binomial parameters"; end if;
      if KI < 0.0 or KI > NI then return 0.0; end if;
      if PF = 0.0 then return (if KI = 0.0 then 1.0 else 0.0); end if;
      if PF = 1.0 then return (if KI = NI then 1.0 else 0.0); end if;
      
      return Float (Exp (Long_Gamma.Log_Gamma (NI + 1.0) - Long_Gamma.Log_Gamma (KI + 1.0) - Long_Gamma.Log_Gamma (NI - KI + 1.0) +
                         KI * Log (PF) + (NI - KI) * Log (1.0 - PF)));
   end Binomial_PMF;

   ------------------
   -- Binomial_CDF --
   ------------------
   function Binomial_CDF (K, N, P : Float) return Float is
      KI : constant Long_Float := Long_Float (Float'Floor (K));
      NI : constant Long_Float := Long_Float (Float'Floor (N));
      PF : constant Long_Float := Long_Float (P);
   begin
      if PF < 0.0 or PF > 1.0 or NI < 0.0 then raise Constraint_Error with "Invalid Binomial parameters"; end if;
      if KI < 0.0 then return 0.0; elsif KI >= NI then return 1.0; end if;
      return Float (Long_Beta.Regularized_Beta (1.0 - PF, NI - KI, KI + 1.0));
   end Binomial_CDF;

   -----------------
   -- Binomial_RN --
   -----------------
   function Binomial_RN (N, P : Float) return Float is
      NI : constant Integer := Integer (Float'Floor (N));
      PF : constant Float := P;
      Res : Integer := 0;
   begin
      Ensure_Random_Init;
      for I in 1 .. NI loop
         if Ada.Numerics.Float_Random.Random (Generator) <= PF then
            Res := Res + 1;
         end if;
      end loop;
      return Float (Res);
   end Binomial_RN;

   -----------------
   -- Weibull_PDF --
   -----------------
   function Weibull_PDF (X, Scale, Shape : Float) return Float is
      XF : constant Long_Float := Long_Float (X);
      L  : constant Long_Float := Long_Float (Scale);
      K  : constant Long_Float := Long_Float (Shape);
   begin
      if L <= 0.0 or K <= 0.0 then raise Constraint_Error with "Scale and Shape must be positive"; end if;
      if XF < 0.0 then return 0.0; end if;
      return Float ((K / L) * (XF / L)**(K - 1.0) * Exp (-(XF / L)**K));
   end Weibull_PDF;

   -----------------
   -- Weibull_CDF --
   -----------------
   function Weibull_CDF (X, Scale, Shape : Float) return Float is
      XF : constant Long_Float := Long_Float (X);
      L  : constant Long_Float := Long_Float (Scale);
      K  : constant Long_Float := Long_Float (Shape);
   begin
      if L <= 0.0 or K <= 0.0 then raise Constraint_Error with "Scale and Shape must be positive"; end if;
      if XF < 0.0 then return 0.0; end if;
      return Float (1.0 - Exp (-(XF / L)**K));
   end Weibull_CDF;

   ----------------
   -- Weibull_RN --
   ----------------
   function Weibull_RN (Scale, Shape : Float) return Float is
      U : Float;
   begin
      Ensure_Random_Init;
      U := Ada.Numerics.Float_Random.Random (Generator);
      return Scale * Float ((-Log (1.0 - Long_Float (U)))**(1.0 / Long_Float (Shape)));
   end Weibull_RN;

   -----------------
   -- Laplace_PDF --
   -----------------
   function Laplace_PDF (X, Location, Scale : Float) return Float is
      XF : constant Long_Float := Long_Float (X);
      MU : constant Long_Float := Long_Float (Location);
      B  : constant Long_Float := Long_Float (Scale);
   begin
      if B <= 0.0 then raise Constraint_Error with "Laplace scale must be positive"; end if;
      return Float (Exp (-abs(XF - MU) / B) / (2.0 * B));
   end Laplace_PDF;

   -----------------
   -- Laplace_CDF --
   -----------------
   function Laplace_CDF (X, Location, Scale : Float) return Float is
      XF : constant Long_Float := Long_Float (X);
      MU : constant Long_Float := Long_Float (Location);
      B  : constant Long_Float := Long_Float (Scale);
   begin
      if B <= 0.0 then raise Constraint_Error with "Laplace scale must be positive"; end if;
      if XF < MU then
         return Float (0.5 * Exp ((XF - MU) / B));
      else
         return Float (1.0 - 0.5 * Exp (-(XF - MU) / B));
      end if;
   end Laplace_CDF;

   -----------------
   -- Laplace_IDF --
   -----------------
   function Laplace_IDF (P, Location, Scale : Float) return Float is
      PF : constant Long_Float := Long_Float (P);
      MU : constant Long_Float := Long_Float (Location);
      B  : constant Long_Float := Long_Float (Scale);
   begin
      if B <= 0.0 then raise Constraint_Error with "Laplace scale must be positive"; end if;
      if PF <= 0.0 or PF >= 1.0 then return 0.0; end if; -- Should ideally handle boundary
      if PF < 0.5 then
         return Float (MU + B * Log (2.0 * PF));
      else
         return Float (MU - B * Log (2.0 - 2.0 * PF));
      end if;
   end Laplace_IDF;

   -----------------
   -- Laplace_RN --
   -----------------
   function Laplace_RN (Location, Scale : Float) return Float is
      U : Float;
   begin
      Ensure_Random_Init;
      U := Ada.Numerics.Float_Random.Random (Generator);
      -- Simple inversion method
      return Laplace_IDF (U, Location, Scale);
   end Laplace_RN;

   -----------------
   -- Poisson_IDF --
   -----------------
   function Poisson_IDF (P, Lambda : Float) return Float is
      PF : constant Long_Float := Long_Float (P);
      L  : constant Long_Float := Long_Float (Lambda);
      Sum : Long_Float := 0.0;
      K   : Natural := 0;
   begin
      if PF <= 0.0 then return 0.0; end if;
      if PF >= 1.0 then return Float'Last; end if;
      loop
         Sum := Sum + Long_Float (Poisson_PMF (Float (K), Float (L)));
         exit when Sum >= PF or K > 1000000;
         K := K + 1;
      end loop;
      return Float (K);
   end Poisson_IDF;

   -------------------
   -- Chi_Square_RN --
   -------------------
   function Chi_Square_RN (DF : Float) return Float is
   begin
      return Gamma_RN (DF / 2.0, 0.5);
   end Chi_Square_RN;

   -------------------
   -- Student_T_RN --
   -------------------
   function Student_T_RN (DF : Float) return Float is
      Z : constant Float := Normal_RN (0.0, 1.0);
      V : constant Float := Chi_Square_RN (DF);
   begin
      return Z / Float (Sqrt (Long_Float (V / DF)));
   end Student_T_RN;

   ----------
   -- F_RN --
   ----------
   function F_RN (DF1, DF2 : Float) return Float is
      U1 : constant Float := Chi_Square_RN (DF1);
      U2 : constant Float := Chi_Square_RN (DF2);
   begin
      return (U1 / DF1) / (U2 / DF2);
   end F_RN;

   --  Generic bisection IDF: find x in [Lo, Hi] such that CDF(x) = P.
   --  The CDF must be monotonically non-decreasing.
   generic
      with function CDF_Func (X : Float) return Float;
   function Bisect_IDF (P, Lo, Hi : Float) return Float;

   function Bisect_IDF (P, Lo, Hi : Float) return Float is
      L : Float := Lo;
      H : Float := Hi;
      M : Float;
   begin
      for I in 1 .. 100 loop
         M := (L + H) / 2.0;
         if CDF_Func (M) < P then L := M; else H := M; end if;
         exit when H - L < 1.0e-9;
      end loop;
      return (L + H) / 2.0;
   end Bisect_IDF;

   -----------------------
   -- Chi_Square_IDF --
   -----------------------
   function Chi_Square_IDF (P, DF : Float) return Float is
      function CDF (X : Float) return Float is (Chi_Square_CDF (X, DF));
      function Bisect is new Bisect_IDF (CDF);
   begin
      if P <= 0.0 then return 0.0; end if;
      if P >= 1.0 then return Float'Last; end if;
      return Bisect (P, 0.0, DF + 10.0 * Float (Sqrt (Long_Float (2.0 * DF))));
   end Chi_Square_IDF;

   ----------------------
   -- Student_T_IDF --
   ----------------------
   function Student_T_IDF (P, DF : Float) return Float is
      function CDF (X : Float) return Float is (Student_T_CDF (X, DF));
      function Bisect is new Bisect_IDF (CDF);
   begin
      if P <= 0.0 then return Float'First; end if;
      if P >= 1.0 then return Float'Last; end if;
      return Bisect (P, -1000.0, 1000.0);
   end Student_T_IDF;

   ---------------
   -- F_IDF --
   ---------------
   function F_IDF (P, DF1, DF2 : Float) return Float is
      function CDF (X : Float) return Float is (F_CDF (X, DF1, DF2));
      function Bisect is new Bisect_IDF (CDF);
   begin
      if P <= 0.0 then return 0.0; end if;
      if P >= 1.0 then return Float'Last; end if;
      return Bisect (P, 0.0, 1000.0);
   end F_IDF;

   ----------------
   -- Gamma_IDF --
   ----------------
   function Gamma_IDF (P, Shape, Rate : Float) return Float is
      function CDF (X : Float) return Float is (Gamma_CDF (X, Shape, Rate));
      function Bisect is new Bisect_IDF (CDF);
   begin
      if P <= 0.0 then return 0.0; end if;
      if P >= 1.0 then return Float'Last; end if;
      return Bisect (P, 0.0, Shape / Rate + 50.0 * Float (Sqrt (Long_Float (Shape))) / Rate);
   end Gamma_IDF;

   ------------------
   -- Weibull_IDF --
   ------------------
   function Weibull_IDF (P, Shape, Scale : Float) return Float is
      function CDF (X : Float) return Float is (Weibull_CDF (X, Scale, Shape));
      function Bisect is new Bisect_IDF (CDF);
   begin
      if P <= 0.0 then return 0.0; end if;
      if P >= 1.0 then return Float'Last; end if;
      return Bisect (P, 0.0, Scale * 10.0);
   end Weibull_IDF;

end SData.Statistics;
