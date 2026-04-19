-- ============================================================
-- BOT WHATSAPP — SCHEMA INICIAL COMPLETO
-- Ejecutar de una vez en el SQL Editor de Supabase
-- ============================================================

-- ============================================
-- EXTENSIONES
-- ============================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- TABLA: tenants
-- Cada bot/cliente que corre sobre la plataforma
-- ============================================
CREATE TABLE public.tenants (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(100) NOT NULL,
  meta_phone_number_id VARCHAR(50) NOT NULL UNIQUE,
  meta_access_token TEXT NOT NULL,
  meta_app_secret TEXT NOT NULL,
  meta_verify_token VARCHAR(100) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  config JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_tenants_phone_number_id ON public.tenants(meta_phone_number_id);
CREATE INDEX idx_tenants_is_active ON public.tenants(is_active);

-- ============================================
-- TABLA: contacts
-- Usuarios finales que interactúan con algún bot
-- ============================================
CREATE TABLE public.contacts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  wa_id VARCHAR(20) NOT NULL,
  profile_name VARCHAR(150),
  metadata JSONB DEFAULT '{}'::jsonb,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_tenant_wa_id UNIQUE (tenant_id, wa_id)
);

CREATE INDEX idx_contacts_tenant_wa ON public.contacts(tenant_id, wa_id);
CREATE INDEX idx_contacts_last_seen ON public.contacts(tenant_id, last_seen_at DESC);

-- ============================================
-- TABLA: sessions
-- Estado volátil de cada conversación activa
-- ============================================
CREATE TABLE public.sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  contact_id UUID NOT NULL REFERENCES public.contacts(id) ON DELETE CASCADE,
  current_flow VARCHAR(50) NOT NULL DEFAULT 'main',
  current_step VARCHAR(50) NOT NULL DEFAULT 'start',
  context JSONB DEFAULT '{}'::jsonb,
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '24 hours'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_active_session UNIQUE (tenant_id, contact_id)
);

CREATE INDEX idx_sessions_expires ON public.sessions(expires_at);
CREATE INDEX idx_sessions_contact ON public.sessions(tenant_id, contact_id);

-- ============================================
-- TABLA: message_logs
-- Auditoría de todos los mensajes enviados y recibidos
-- ============================================
CREATE TABLE public.message_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  contact_id UUID REFERENCES public.contacts(id) ON DELETE SET NULL,
  wa_message_id VARCHAR(100),
  direction VARCHAR(10) NOT NULL CHECK (direction IN ('inbound', 'outbound')),
  message_type VARCHAR(30) NOT NULL,
  content JSONB NOT NULL,
  status VARCHAR(20),
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_logs_tenant_created ON public.message_logs(tenant_id, created_at DESC);
CREATE INDEX idx_logs_wa_message_id ON public.message_logs(wa_message_id);
CREATE INDEX idx_logs_contact ON public.message_logs(contact_id);

-- ============================================
-- TABLA: tenant_users
-- Vincula auth.users con tenants (para el dashboard)
-- ============================================
CREATE TABLE public.tenant_users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id UUID NOT NULL REFERENCES public.tenants(id) ON DELETE CASCADE,
  role VARCHAR(20) NOT NULL DEFAULT 'admin' CHECK (role IN ('admin', 'operator', 'viewer')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_user_tenant UNIQUE (user_id, tenant_id)
);

CREATE INDEX idx_tenant_users_user ON public.tenant_users(user_id);
CREATE INDEX idx_tenant_users_tenant ON public.tenant_users(tenant_id);

-- ============================================
-- TRIGGER: updated_at automático
-- ============================================
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_tenants_updated BEFORE UPDATE ON public.tenants
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_sessions_updated BEFORE UPDATE ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================
-- HELPER: tenant del usuario autenticado
-- ============================================
CREATE OR REPLACE FUNCTION public.current_user_tenant_id()
RETURNS UUID AS $$
  SELECT tenant_id FROM public.tenant_users
  WHERE user_id = auth.uid()
  LIMIT 1;
$$ LANGUAGE SQL STABLE SECURITY DEFINER;

-- ============================================
-- ROW LEVEL SECURITY
-- ============================================
ALTER TABLE public.tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tenant_users ENABLE ROW LEVEL SECURITY;

-- Policy: un usuario solo ve su propio vínculo
CREATE POLICY "user_sees_own_tenant_link" ON public.tenant_users
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Policy: el usuario solo ve/edita su tenant
CREATE POLICY "tenant_isolation_tenants" ON public.tenants
  FOR ALL TO authenticated
  USING (id = public.current_user_tenant_id());

-- Policies de aislamiento por tenant
CREATE POLICY "tenant_isolation_contacts" ON public.contacts
  FOR ALL TO authenticated
  USING (tenant_id = public.current_user_tenant_id());

CREATE POLICY "tenant_isolation_sessions" ON public.sessions
  FOR ALL TO authenticated
  USING (tenant_id = public.current_user_tenant_id());

CREATE POLICY "tenant_isolation_logs" ON public.message_logs
  FOR ALL TO authenticated
  USING (tenant_id = public.current_user_tenant_id());

-- ============================================
-- FIN DEL SCHEMA
-- ============================================
-- PRÓXIMOS PASOS MANUALES:
-- 1. Insertar tu primer tenant:
--
-- INSERT INTO public.tenants (
--   name, meta_phone_number_id, meta_access_token,
--   meta_app_secret, meta_verify_token
-- ) VALUES (
--   'Mi Cliente',
--   'TU_PHONE_NUMBER_ID',
--   'TU_ACCESS_TOKEN',
--   'TU_APP_SECRET',
--   'TU_VERIFY_TOKEN'
-- );
--
-- 2. Crear un usuario en Authentication > Users (email + password)
--
-- 3. Vincular el usuario con el tenant:
--
-- INSERT INTO public.tenant_users (user_id, tenant_id, role)
-- VALUES (
--   'UUID_DEL_USUARIO',  -- copiar de Authentication > Users
--   'UUID_DEL_TENANT',   -- copiar del INSERT anterior
--   'admin'
-- );
-- ============================================
